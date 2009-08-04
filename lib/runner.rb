#!/usr/bin/env ruby

require 'lib/parser'
require 'lib/mysqlmb'
require 'lib/helpers'
include SimpleMail
include DateFormat
include FileSize

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
          mail_message += "Successfull backup: #{message} \n"
        else
          mail_message += "Backup of MySQL failed: #{message} \n"
        end
        # calculate size of all backups just made
        backup_size = FileSize.fsize(mysqlmaint.backup_size(start_time))
        mail_message += "Backup file size after compression: #{backup_size} \n"
  
        if maintenance_error == 0 && @options[:retention] > 0
          cleanup = mysqlmaint.delete_old_backups(@options[:retention], @options[:force])
          mail_message += cleanup_message(cleanup)
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
          dbs = mysqlmaint.get_databases( @options[:databases], :mysql)
          puts "Found #{dbs.size} database(s):"
          dbs.each { |db| puts db }
        else
          backup_day =  @options[:restore_offset]
          dbs = mysqlmaint.get_databases( @options[:databases], :backup, {:day => backup_day})
          puts "Found #{dbs.size} database backup(s) for #{mysqlmaint.back_date(backup_day)}:"
          dbs.each { |db| puts db.file_name }
        end
      when "cleanup"
        cleanup = mysqlmaint.delete_old_backups(@options[:retention], @options[:force])
        mail_message += cleanup_message(cleanup)
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

    def cleanup_message(cleanup)
      message = "Old backups removed: \n"
      message += "no backups deleted \n" if (cleanup.empty? || !@options[:force])
      message += "Use option \"force\" to delete backups \n" if !@options[:force]
      cleanup.each do |file|
        message += " #{file}\n"
      end
      message
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
