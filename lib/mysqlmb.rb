module MySqlMb

class MySQLMaint 
  require "logger"
  require "find"
  
  # MySQL system databases
  SYSTEM_DATABASES = %w[mysql information_schema]
  
  def initialize(connection, paths, params)
    @user = connection[:user]
    @password = connection[:password]
    @host = connection[:host]
    @credentials = "--user=#{@user} --password=#{@password}"
    @date_format = params[:date_format] || "%Y-%m-%d"
    @verbose = params[:verbose] || false 
    logfile = File.open(paths[:logfile], File::WRONLY | File::APPEND | File::CREAT)
    @logger = Logger.new(logfile, 10, 1024000)
    @paths = {}
    paths.each { |key, value| @paths[key] = rm_slash(value) }
  end

  def db_backup(databases=[])
    puts "[--] Start datbase backup..." if @verbose
    error_count = 0

    # check for emptiness or keyword within db-Array
    databases = get_databases(databases)

    databases.each do |db|
      dump_file = "#{@paths[:backup]}/#{back_date()}-#{db}"
      @logger.add(Logger::INFO, "Backing up database #{db} ...")
      %x[#{@paths[:mysqldump]} --opt --flush-logs --allow-keywords -q -a -c #{@credentials} --host=#{@host} #{db} > #{dump_file}.tmp]
      if $? == 0
        %x[mv #{dump_file}.tmp #{dump_file}; bzip2 -f #{dump_file}]
        message = "[OK] Successfully backed up database: #{db}"
        puts message if @verbose
        @logger.add(Logger::INFO, message)
      else
        error_count += 1
        message = "[!!] Backup failed on database: #{db}"
        puts message if @verbose
        @logger.add(Logger::ERROR, "#{message}, user: #{@user}, using password: #{@password.empty?}")
      end
    end
    msg = "#{databases.size - error_count} from #{databases.size} databases backed up successfully"
    puts "[--] End of backup: #{msg}" if @verbose
    return error_count, msg
  end

  def db_restore(databases, days = 1)
    puts "Start restoring databases..." if @verbose
    error_count = 0
    all_dbs = all_databases()
    
    # check for emptiness or keyword within db-Array
    databases = get_databases(databases, "backup", -(days))
    
    date = back_date(-(days))

    databases.each do |db|
     # make sure the database exists
     unless all_dbs.include?(db)
       %x[echo CREATE DATABASE \\`#{db}\\` | #{@paths[:mysql]}  #{@credentials}]
       if $? != 0
         error_count += 1
         message = "[!!] can't create database #{db} message: #{$?}"
         @logger.add(Logger::ERROR, message + " , user: #{@user}, using password: #{!@password.empty?}")
         puts message if @verbose
         next
       else 
         message = "[OK] created database #{db}"
         puts message if @verbose
         @logger.add(Logger::INFO, message)
       end
     end

     dump_file = "#{@paths[:backup]}/#{date}-#{db}"
     
     # decompress dump file if the file exists
     %x[bunzip2 -k #{dump_file}.bz2] if File.exist?("#{dump_file}.bz2")

     # restore database
     %x[#{@paths[:mysql]} #{@credentials} --host=#{@host} #{db} < #{dump_file}]
     if $? != 0
       error_count += 1
       message = "[!!] can't restore database #{db} message: #{$?}"
       @logger.add(Logger::ERROR, message + " , user: #{@user}, using password: #{!@password.empty?}")
       puts message if @verbose
       next
     else
       message = "[OK] restored database #{db}"
       puts message if @verbose
     end

     # delete decompressed backup file
     File.delete(dump_file)
     #%x[rm -f #{dump_file}]
    end

    msg = "#{databases.size - error_count} from #{databases.size} databases restored successfully"
    puts "[--] End of restore: #{msg}" if @verbose
    return error_count, msg
  end

  def delete_old_backups(retention = 30, force = false)
    filelist = []
    file_filter = ".*\.bz2"
 
   # retention in days: date back from now
    retention_date = Time.now - (retention * 3600 * 24)
    puts "[--] Delete backups older than #{retention} days:" if @verbose && force
    puts "[--] Listing  backups older than #{retention} days which would be deleted if you use the --force/-f option:" if @verbose && !force
    begin
      Find.find(@paths[:backup]) do  |f|
        if File.stat(f).mtime < retention_date
          if File.basename(f) =~ /#{file_filter}/ 
	    filelist << File.basename(f)
            puts "[--] remove #{filelist.last}" if @verbose
            File.delete(f) if force
          end
        end
      end
    rescue StandardError => e
      abort "[!!] Error deleting old backups :" + e.message
    end
    puts "[--] no backups removed" if @verbose && filelist.empty?
    filelist
  end

  def chkdb()
    puts "[--] Start mysqlcheck, this could take a moment..." if @verbose
    check = %x[#{@paths[:mysqlcheck]} --optimize -A #{@credentials} --host=#{@host}]
    @logger.add(Logger::INFO, check)
    puts check if @verbose
  end

  def backup_size(time = Time.at(0))
    size = 0.0
    file_filter = ".*\.bz2$"
    abort "Abort: input value must be an instance of Time" unless time.instance_of?(Time)
    begin
      Find.find("/var/backups/mysql") do  |f|
        if File.stat(f).ctime > time && File.basename(f) =~ /#{file_filter}/
          size += File.stat(f).size
        end
      end
    rescue RegexpError => e
      abort "Invalid filter \"#{file_filter}\" in method backup_size."  
    end
    size
  end

  def get_databases(databases = [], source = "mysql", adjustment = 0) 
    # check for emptiness or keyword within db-Array
    if databases.empty? || databases.include?("all")
      return all_databases(source, adjustment)
    elsif databases.include?("user")
      return user_databases(source, adjustment)
    elsif databases.include?("system")
      return system_databases()
    else
      return databases
    end
  end
  
  def back_date(adjustment = 0)
    (DateTime::now + (adjustment)).strftime(@date_format)
  end

  private

  def all_databases(source = "mysql", time = 0)
    case source
    when "mysql"
      databases = %x[echo "show databases" | #{@paths[:mysql]} #{@credentials} | grep -v Database].split("\n")
      if $? != 0
        @logger.add(Logger::ERROR, "mysql \"show databases\" failed: return value #{$?}, user: #{@user}, using password: #{!@password.empty?}")
        exit
      end
      return databases
    when "backup"
      databases = []
      backups = %x[find #{@paths[:backup]} -maxdepth 1 -type f -name #{back_date(time)}*.bz2].split("\n")
      if $? != 0
        puts $?
        exit
      end
      backups.each { |file| databases << file.match(/#{@paths[:backup]}\/#{back_date(time)}-(.+).bz2$/)[1] }
      return databases
    end
  end

  def user_databases(source = "mysql", adjustment = 0)
    dbs = all_databases(source, adjustment) - system_databases()
    dbs
  end

  def system_databases
    SYSTEM_DATABASES
  end

  # removes trailing slashed from path
  def rm_slash(path)
    path.gsub(/\/+$/, '')
  end

end # class
end # module
