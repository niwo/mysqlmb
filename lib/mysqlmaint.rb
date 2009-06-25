class MySQLMaint
  require "logger"

  attr_accessor(:user, :password, :host, :backup_path, :mysql_path, :verbose)

  def initialize(user, password, host, backup_path, mysql_path, logfile_path, verbose=false)
    @user = user
    @password = password
    @credentials = "--user=#{user} --password=#{password}"
    @host = host
    @backup_path = backup_path
    @mysql_path = mysql_path
    @verbose = verbose 
    logfile = File.open(logfile_path, File::WRONLY | File::APPEND | File::CREAT)
    @logger = Logger.new(logfile, 10, 1024000)
  end

  def db_backup(databases=[])
    error_count = 0
    if databases.empty? || databases.include?("all")
      databases = %x[echo "show databases" | mysql #{@credentials} | grep -v Database].split("\n")
      if $? != 0
        @logger.add(Logger::ERROR, "mysql show \"databases failed\": return value #{$?}, user: #{user}, using password: #{!password.empty?}")
        exit
      end
    end

    databases.each do |db|
      dump_file = "#{@backup_path}/#{back_date}-#{db}"
      @logger.add(Logger::INFO, "Backing up database #{db} ...")
      puts rslt = %x[#{@mysql_path}/mysqldump --opt --flush-logs --allow-keywords -q -a -c #{@credentials} --host=#{host} #{db} > #{dump_file}.tmp]
      if $? == 0
        %x[mv #{dump_file}.tmp #{dump_file}; bzip2 -f #{dump_file}]
        message = "++ Successfully backed up database: #{db}"
        puts message if @verbose
        @logger.add(Logger::INFO, message)
      else
        error_count += 1
        message = "!! Backup failed on database: #{db}"
        puts message if @verbose
        @logger.add(Logger::ERROR, "#{message}, user: #{user}, using password: #{password.empty?}")
      end
    end
    puts msg = "#{databases.size - error_count} from #{databases.size} databases backed up successfully"
    return error_count, msg
  end

  def delete_old_backups(retention_time=30)
    %x[find #{@backup_path} -maxdepth 1 -type f -mtime +#{retention_time} -exec rm -vf {} \\;]
  end

  def chkdb()
    check = %x[#{@mysql_path}/mysqlcheck --optimize -A #{@credentials} --host=#{host}]
    @logger.add(Logger::INFO, check)
    puts check if @verbose
  end

  def backup_size
    backup_size =%x[du -hsc #{@backup_path}/#{back_date}-*.bz2 | awk '{print $1}' | tail -n 1]
    puts("Compressed backup size: #{backup_size}") if @verbose
    backup_size
  end

  private
  def back_date
    DateTime::now.strftime("%d-%m-%Y")
  end
end
