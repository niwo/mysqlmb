module MySqlMb

class MySQLMaint 
  require "logger"
  
  # MySQL system databases
  SYSTEM_DATABASES = %w[mysql information_schema]
  
  def initialize(connection, paths, params)
    @user = connection[:user]
    @password = connection[:password]
    @host = connection[:host]
    @credentials = "--user=#{@user} --password=#{@password}"
    @backup_path = rm_slash(paths[:backup])
    @mysql_path = rm_slash(paths[:mysql])
    @date_format = params[:date_format] || "%Y-%m-%d"
    @verbose = params[:verbose] || false 
    logfile = File.open(paths[:logfile], File::WRONLY | File::APPEND | File::CREAT)
    @logger = Logger.new(logfile, 10, 1024000)
  end

  def db_backup(databases=[])
    error_count = 0

    # check for emptiness or keyword within db-Array
    databases = get_databases(databases)

    databases.each do |db|
      dump_file = "#{@backup_path}/#{back_date()}-#{db}"
      @logger.add(Logger::INFO, "Backing up database #{db} ...")
      %x[#{@mysql_path}/mysqldump --opt --flush-logs --allow-keywords -q -a -c #{@credentials} --host=#{@host} #{db} > #{dump_file}.tmp]
      if $? == 0
        %x[mv #{dump_file}.tmp #{dump_file}; bzip2 -f #{dump_file}]
        message = "INFO: Successfully backed up database: #{db}"
        puts message if @verbose
        @logger.add(Logger::INFO, message)
      else
        error_count += 1
        message = "ERROR: Backup failed on database: #{db}"
        puts message if @verbose
        @logger.add(Logger::ERROR, "#{message}, user: #{user}, using password: #{password.empty?}")
      end
    end
    msg = "#{databases.size - error_count} from #{databases.size} databases backed up successfully"
    puts "INFO: End of backup: #{msg}" if @verbose
    return error_count, msg
  end

  def db_restore(databases, days = 1)
    error_count = 0
    all_dbs = all_databases()
    
    # check for emptiness or keyword within db-Array
    databases = get_databases(databases, "backup", -(days))
    
    date = back_date(-(days))

    databases.each do |db|
     # make sure the database exists
     unless all_dbs.include?(db)
       %x[echo CREATE DATABASE \\`#{db}\\` | mysql #{@credentials}]
       if $? != 0
         error_count += 1
         message = "ERROR: can't create database #{db} message: #{$?}"
         @logger.add(Logger::ERROR, message + " , user: #{user}, using password: #{!password.empty?}")
         puts message if @verbose
         next
       else 
         message = "INFO: created database #{db}"
         puts message if @verbose
         @logger.add(Logger::INFO, message)
       end
     end

     dump_file = "#{@backup_path}/#{date}-#{db}"
     
     # decompress dump file
     %x[bunzip2 -k #{dump_file}.bz2]
     # restore database
     %x[mysql #{@credentials} --host=#{@host} #{db} < #{dump_file}]
     if $? != 0
       error_count += 1
       message = "ERROR: can't restore database #{db} message: #{$?}"
       @logger.add(Logger::ERROR, message + " , user: #{user}, using password: #{!password.empty?}")
       puts message if @verbose
       next
     else
       message = "INFO: restored database #{db}"
       puts message if @verbose
     end

     # delete decompressed backup file
     %x[rm -f #{dump_file}]
    end

    msg = "#{databases.size - error_count} from #{databases.size} databases restored successfully"
    puts "INFO: End of restore: #{msg}" if @verbose
    return error_count, msg
  end

  def delete_old_backups(retention_time=30)
    msg = %x[find #{@backup_path} -maxdepth 1 -type f -mtime +#{retention_time} -exec rm -vf {} \\;]
    if @verbose
      msg.empty? ? puts("INFO: No backup files deleted") : puts("INFO: #{msg}")
    end
    msg
  end

  def chkdb()
    check = %x[#{@mysql_path}/mysqlcheck --optimize -A #{@credentials} --host=#{@host}]
    @logger.add(Logger::INFO, check)
    puts check if @verbose
  end

  def backup_size
    backup_size =%x[du -hsc #{@backup_path}/#{back_date}-*.bz2 | awk '{print $1}' | tail -n 1]
    puts("INFO: Compressed backup file size: #{backup_size}") if @verbose
    backup_size
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
      databases = %x[echo "show databases" | mysql #{@credentials} | grep -v Database].split("\n")
      if $? != 0
        @logger.add(Logger::ERROR, "mysql \"show databases\" failed: return value #{$?}, user: #{@user}, using password: #{!@password.empty?}")
        exit
      end
      return databases
    when "backup"
      databases = []
      backups = %x[find #{@backup_path} -maxdepth 1 -type f -name #{back_date(time)}*.bz2].split("\n")
      if $? != 0
        puts $?
        exit
      end
      backups.each { |file| databases << file.match(/#{@backup_path}\/#{back_date(time)}-(.+).bz2$/)[1] }
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