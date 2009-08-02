#!/usr/bin/env ruby

require 'lib/parser'
require 'lib/mysqlmb'

module MySqlMb
  
  class Runner
    
    def initialize(args)
      @args = args
    end
    
    def run(command)
      load_options(command)
      
      start_time = Time.now
      mail_message = mail_header(command, start_time)
      mysqlmaint = MySQLMaint.new(@connection, @paths, @options)
  
      maintenance_error = 0
      
      case command
      when "restore"
        mysqlmaint.db_restore(@options[:databases], @options[:restore_offset])
      when "backup"
        maintenance_error, message = mysqlmaint.db_backup(@options[:databases])
        if maintenance_error == 0
          mail_message += "All databases successfully backed up: #{message} \n"
        else
          mail_message += "Backup of MySQL failed: #{message} \n"
        end
        # calculate size of all backups
        backup_size = mysqlmaint.backup_size
        mail_message += "Backup file size after compression: #{backup_size} \n"
  
        if maintenance_error == 0 && @options[:retention] > 0
          cleanup = mysqlmaint.delete_old_backups(@options[:retention])
          cleanup = "no backups deleted" if cleanup.empty?
          mail_message += "Old backups removed: \n#{cleanup}\n"
        end
  
        if @options[:optimize]
          mysqlmaint.chkdb()
          mail_message += "All databases have been optimized with mysqlcheck\n"
        end
      when "optimize"
        mysqlmaint.chkdb()
        mail_message += "All databases have been optimized with mysqlcheck\n"
      when "list"
        if @options[:list_type] == :mysql
          dbs = mysqlmaint.get_databases( @options[:databases], "mysql" )
          puts "Found #{dbs.size} database(s):"
          dbs.each { |db| puts db }
        else
          dbs = mysqlmaint.get_databases( @options[:databases], "backup", -(@options[:restore_offset]), true)
          puts "Found #{dbs.size} database backup(s) for #{mysqlmaint.back_date(-(@options[:restore_offset]))}:"
          dbs.each { |db| puts db }
        end
      end
  
      execution_time = fduration(Time.now - start_time)
      mail_message += "----------\nMaintenance duration: #{execution_time} \n"
  
      # send confirmation email
      if @options[:mail] && !@options[:mail_to].empty?
        mail_subject = "MySQL Maintenence"
        maintenance_error != 0 ? mail_subject += " - failed" :  mail_subject += " - successful"
        SimpleMail.send_email("mysql@#{@connection[:host]}", "", @options[:mail_to], "", mail_subject, mail_message)
      end
  
      if @options[:verbose] && %w[backup restore optimize].include?(command)
        puts "Maintenance duration: #{execution_time}"
      end
    end
    
    private 
    
    def load_options(command)
      @connection, @paths, @options = Parser.new.parse(command, @args)
    end
  
    def mail_header(command, start_time)
      mail_message = <<END
----------------------------------------------------------
                MySQL maintenance on #{@connection[:host]}
                  #{start_time.strftime("%d-%m-%Y")}
----------------------------------------------------------
Settings:
  #{@options[:retention]} days backup retention time
  Action: #{command}
  Database optimization enabled: #{@options[:optimize]}
----------
END
    end
  
  end # class
end # module
