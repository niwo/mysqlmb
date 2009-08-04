module MySqlMb

class MySQLMaint 
  require "logger"
  require "find"
  require "lib/backup"
  
  # MySQL system databases
  SYSTEM_DATABASES = %w[mysql information_schema]
  
  def initialize(connection, paths, params)
    # set connection parameters
    @user = connection[:user]
    @password = connection[:password]
    @host = connection[:host]
    @credentials = "--user=#{@user} --password=#{@password}"
    
    # set params or default 
    @date_format = params[:date_format] || "%Y-%m-%d"
    @verbose = params[:verbose] || false 
    
    # initialize log file
    logfile = File.open(paths[:logfile], File::WRONLY | File::APPEND | File::CREAT)
    @logger = Logger.new(logfile, 10, 1024000)

    # set all paths
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
        File.rename("#{dump_file}.tmp", dump_file)
        %x[bzip2 -f #{dump_file}]
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

  def db_restore(databases, day = -1)
    puts "Start restoring databases..." if @verbose
    error_count = 0
    all_dbs = all_databases()
    
    # check for emptiness or keyword within db-Array
    databases = get_databases(databases, :backup, {:day => day})
    
    date = back_date(day)

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
    end

    msg = "#{databases.size - error_count} from #{databases.size} databases restored successfully"
    puts "[--] End of restore: #{msg}" if @verbose
    return error_count, msg
  end

  def delete_old_backups(retention = 30, force = false)
    filelist = []
 
    # retention in days: date back from now
    retention_date = Time.now - (retention * 3600 * 24)

    if @verbose
      if force
        puts "[--] Delete backups older than #{retention} days:"
      else
        puts "[--] Listing  backups older than #{retention} days which would be deleted if you use the --force/-f option:"
      end
    end

    begin
      get_backup_files(Time.at(0)).each do |f|
        if File.stat(f).mtime < retention_date
	  filelist << File.basename(f)
          puts "[--] remove #{filelist.last}" if @verbose
          File.delete(f) if force
        end
      end
    rescue StandardError => e
      abort "[!!] Error deleting old backups :" + e.message
    end
    puts "[--] No backups removed" if @verbose && filelist.empty?
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
    get_backup_files(time).each do |f|
      size += File.stat(f).size
    end
    size
  end

  def get_databases(databases = [], source = :mysql, options = {}) 
    # check for emptiness or keyword within db-Array
    type = case databases[0]
      when "all" || nil then :all
      when "user" then :user
      when "system" then :system
    end
    
    if source == :mysql
      return database_filter(databases, type) unless type
      return databases({:type => type})
    elsif source == :backup
      return database_filter(databases, type, {:type => :backup, :day => options[:day]}) unless type
      return backups(options[:day], {:type => type})
    else
      return databases
    end
  end
  
  def back_date(adjustment = 0)
    (DateTime::now + adjustment).strftime(@date_format)
  end

  private

  def get_backup_files(time_limit, options = {})
    abort "Abort: input value must be an instance of Time" unless time_limit.instance_of?(Time)
    file_filter = options[:file_filter] || ".*\.bz2$"
    files = []
    begin
      Find.find(@paths[:backup]) do |f|
        if File.stat(f).ctime > time_limit && File.basename(f) =~ /#{file_filter}/
          files << f
        end
      end
    rescue RegexpError => e
      abort "Invalid filter \"#{file_filter}\" in get_backup_files."
    end
    files.sort
  end

  def databases(options = {})
    # ask mysql for a list of all dbs, remove first entry which reads "Databases"
    dbs = %x[echo "show databases" | #{@paths[:mysql]} #{@credentials}].split("\n")[1..-1]

    if $? != 0
      error = "mysql \"show databases\" failed: return value #{$?}, user: #{@user}, using password: #{!@password.empty?}"
      @logger.add(Logger::ERROR, error)
      abort error
    end
    return dbs.sort if  options[:type] == :all
    database_filter(dbs.sort, options[:type])
  end

  def backups(day = 0, options = {})
    time_limit = Time.now - ((-(day) + 1) * 3600 * 24)
    extension = options[:extension] || "\.bz2"
    backups = []
    date = back_date(day)
    get_backup_files(time_limit).each do |f|
      if File.basename(f).match(/#{date}-.+#{extension}$/)
        backup = MySqlMb::Backup.new(File.basename(f).match(/#{date}-(.+)#{extension}$/)[1],
                                     day,
                                     File.expand_path(f))
        backups << backup
      end
    end
    return backups.sort if options[:type] == :all
    database_filter(backups.sort, options[:type], {:day => day})
  end

  def database_filter(databases, type, options = {})
    source = options[:source] || :mysql
    case type
    when :all
      return databases 
    when :system
      return databases & SYSTEM_DATABASES
    when :user
      return databases - SYSTEM_DATABASES
    else
      # handle cases when individual dbs are provided
      if source == :mysql
        return databases & databases({:type => :all})
      elsif source == :backup
        return databases & backups(options[:day], {:type => :all})
      end
    end
    databases
  end

  # removes trailing slashed from path
  def rm_slash(path)
    path.gsub(/\/+$/, '')
  end

end # class
end # module
