#!/usr/bin/env ruby

require 'lib/config'
require 'lib/mysqlmb'
require 'lib/helpers'

module MySqlMb  
  class Runner
    # all commands
    CMD = %w[backup restore optimize cleanup list help]

    # commands which require no MySQL user/password
    NO_CREDENTIALS = { 'list' => {:list_type => :backup},
                       'cleanup' => {},
                       'help' => {} } 

    def initialize(config)
      @config = config
    end
    
    def run(command)
      verify_input(command)

      start_time = Time.now
      mail_message = mail_header(command, start_time)
      mysqlmaint = MySQLMaint.new(@config.connection, @config.paths, @config.options)
      
      if @config.options.debug
        puts @config.to_s
        exit
      end

      maintenance_error = 0
      
      case command
      when "help"
      when "restore"
        mysqlmaint.db_restore(@config.options.databases, @config.options.restore_offset)
      when "backup"
        maintenance_error, message = mysqlmaint.db_backup(@config.options.databases)
        if maintenance_error == 0
          mail_message += "Successfull backup: #{message}\n"
        else
          mail_message += "Backup of MySQL failed: #{message}\n"
        end
        # calculate size of all backups just made
        backup_size = Text.fsize(mysqlmaint.backup_size(start_time))
        mail_message += "Backup file size after compression: #{backup_size}\n"
  
        if maintenance_error == 0 && @config.options.retention > 0
          cleanup = mysqlmaint.delete_old_backups(@config.options.retention, @config.options.force)
          mail_message += cleanup_message(cleanup)
        end
      when "optimize"
        mysqlmaint.chkdb()
        mail_message += "All databases have been optimized with mysqlcheck\n"
      when "list"
        if @config.options.list_type == :mysql
          dbs = mysqlmaint.get_databases(@config.options.databases, :mysql)
          puts "Found #{dbs.size} database(s):"
          dbs.each { |db| puts db }
        else
          backup_day =  @config.options.restore_offset
          dbs = mysqlmaint.get_databases(@config.options.databases, :backup, {:day => backup_day})
          puts "Found #{dbs.size} database backup(s) for #{mysqlmaint.back_date(backup_day)}:"
          dbs.each { |db| puts db.file_name }
        end
      when "cleanup"
        cleanup = mysqlmaint.delete_old_backups(@config.options.retention, @config.options.force)
        mail_message += cleanup_message(cleanup)
      end
  
      execution_time = Text.fduration(Time.now - start_time)
      mail_message += "----------\nMaintenance duration: #{execution_time}\n"
  
      # send confirmation email
      if @config.options.mail && !@config.options.mail_to.empty?
        mail_subject = "MySQL Maintenence"
        maintenance_error != 0 ? mail_subject += " - failed" :  mail_subject += " - successful"
        SimpleMail.send_email("mysql@#{@config.connection.host}", @config.options.mail_to, mail_subject, mail_message, {:mail_host => @config.options.mail_host})
      end
  
      if @config.options.verbose && %w[backup restore optimize].include?(command)
        puts "Maintenance duration: #{execution_time}"
      end
    end
    
    private

    def verify_input(command)
      if missing_credentials? command
        puts "Please provide at least a password for MySQL user \"#{@config.connection.user}\""
        return false
      end

      unless @config.options.version || CMD.include?(command)
        puts "Please provide a valid action argument:"
        return false
      end
    end

    def missing_credentials?(command)
      if (@config.connection.user == '' || @config.connection.password == '') &&  @config.options.debug == false
        if NO_CREDENTIALS.has_key?(command)
          return false if NO_CREDENTIALS[command].empty?
          @config.options.each {|key, value| return false if NO_CREDENTIALS[command][key] === value }
          return true
        end
        return true
      end
      false
    end

    def cleanup_message(cleanup)
      message = "Old backups removed:\n"
      message << "No backups deleted\n" if (cleanup.empty? || !@config.options.force)
      message << "Use option \"force\" to delete backups\n" if !@config.options.force
      cleanup.each do |file|
        message << " #{file}\n"
      end
      message
    end
  
    def mail_header(command, start_time)
      mail_message =<<-END
-------------------------------------------------------------------
  MySQL maintenance on #{@config.connection.host}
  #{start_time.strftime("Start Time: %a %d.%m.%Y %H:%M")}
-------------------------------------------------------------------
Settings:
  Retention time: #{@config.options.retention} days
  Action: #{command}
  Database optimization enabled: #{@config.options.optimize}
----------
      END
    end
  
  end # class
end # module
