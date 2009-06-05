module MySQLMaint
  attr_accessor(:credentials, :host, :backup_path, :mysql_path, :verbose)

  def db_backup(databases=[])
    error_count = 0
    if databases.empty?
      databases = %x[echo "show databases" | mysql #{@credentials} | grep -v Database].split("\n")
    end

    databases.each do |db|
      dump_file = "#{@backup_path}/#{back_date}-#{db}"
      rslt = %x[#{@mysql_path}/mysqldump --opt --flush-logs --allow-keywords -q -a -c #{@credentials} #{db} --host=#{host}> #{dump_file}.tmp]
      puts rslt
      if rslt.empty?
        %x[mv #{dump_file}.tmp #{dump_file};bzip2 -f #{dump_file}]
        puts "++ Successfully backed up database: #{db}" if @verbose
      else
        error_count += 1
        puts "!! Backup failed on database: #{db}" if @verbose
      end
    end
    puts "#{databases.size - error_count} from #{databases.size} databases backed up successfully"
    error_count
  end

  def delete_old_backups(retention_time=30)
    %x[find #{@backup_path} -maxdepth 1 -type f -mtime +#{retention_time} -exec rm -vf {} \\;]
  end

  def chkdb()
    check = Proc.new { %x[#{@mysql_path}/mysqlcheck --optimize -A #{@credentials} --host=#{host}] }
    @verbose ? puts(check.call()) : check.call()
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
