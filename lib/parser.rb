#!/usr/bin/env ruby
  
require 'optparse'
require 'date'
require 'yaml'
include SimpleMail
include DateFormat
  
module MySqlMb

  class Parser
    def initialize()
  
    end
  
    def parse(args)
      # Options Parser
      connection = {}
      paths = {:logfile => APP_PATH + "/log/mysqlmb.log"}
      options = {}
  
      optparse = OptionParser.new do |opts|
      # Set a banner, displayed at the top
      # of the help screen.
      opts.banner = "Usage: mysqlmb.rb COMMAND [options]"
      opts.program_name = "MySQL Maintenance Buddy"
      opts.version = "1.1"
      opts.summary_width = 30
      opts.summary_indent = "  "
      opts.separator ""
      opts.separator "List of Commands:"
      opts.separator "  backup \t\t\t Backup databases"
      opts.separator "  restore \t\t\t Restore databases"
      opts.separator "  optimize \t\t\t Optimize databases"
      opts.separator "  list-db \t\t\t List databases"
      opts.separator "  list-bak \t\t\t List database backups"
      opts.separator ""
      opts.separator "Options:"
  
      # Define the options, and what they do
      @config_file = nil
      opts.on( '-c', '--config-file FILE', 'Specify a configuration file which contains all options',                                          'see config/config.rb.orig for an example' ) do |file|
        @config_file = file
        unless File.exists?(file)
          puts "Abort: No configuration file found!\nSee #{APP_PATH}/config/mysqlmb.conf.dist for an example."
          exit
        end
      end
  
      @databases ||= []
      opts.on( '-d', '--databases db1,db2,db3', Array, 'Define which databases to backup (default: all)',
                                                       'Syntax: database1,database2',
                                                       'Keywords: all, user, system') do |db|
        @databases = db
      end
  
      options[:optimize] ||= true
      opts.on( '--[no-]optimize', 'Disable database optimization' ) do |o|
        options[:optimize] = o
      end
  
      options[:retention] ||= 30
      opts.on( '-r', '--retention-time DAYS', Integer, 'How many days to keep the db backups (default: 30 days)' ) do |days|
        options[:retention] = days
      end
  
      options[:restore_offset] = 1
      opts.on( '-o', '--restore-offset DAYS', Integer, 'How old are the backups to restore (default: 1 day)' ) do |days|
        options[:restore_offset] = days
      end
  
      connection[:host] ||= 'localhost'
      opts.on( '-h', '--host HOST', 'MySQL hostname (default: localhost)' ) do |host|
        connection[:host] = host
      end
  
      connection[:user] ||= 'backup'
      opts.on( '-u', '--user USER', 'MySQL backup user (default: backup)' ) do |user|
        connection[:user] = user
      end
  
      connection[:password] ||= ''
      opts.on( '-p', '--password PASSWORD', 'MySQL password' ) do |password|
        connection[:password] = password
      end
  
      options[:mail_to] ||= ''
      opts.on( '-m', '--mail-to MAIL-ADDRESS', 'email address to send reports to' ) do |mail|
        options[:mail_to] = mail
      end
  
      options[:mail] ||= 'false'
      opts.on( '--[no-]mail', 'activate/deactivate mail messages' ) do |mail|
        options[:mail] = mail
      end
  
      paths[:backup] ||=  File.expand_path(APP_PATH, '/backups')
      opts.on( '--backup-path PATH', "backup storage directory (default: #{paths[:backup]})" ) do |backup_path|
        paths[:backup] = backup_path
      end
  
      paths[:mysql] ||= '/usr/bin/'
      opts.on( '--mysql-path PATH', 'Specify the MySQL utility path (default: /usr/bin/)' ) do |mysql_path|
        paths[:mysql] = mysql_path
      end
  
      options[:verbose] = false
        opts.on( '-v', '--verbose', 'Output more information' ) do
        options[:verbose] = true
      end
  
      options[:date_format] ||= "%Y-%m-%d"
      opts.on( '--date-format FORMAT', 'Date format for backup file name (default: %Y-%m-%d)' ) do |format|
        options[:date_format] = format
      end
  
      options[:debug] = false
      opts.on( '--debug', 'Debugging mode: show arguments passed' ) do
        options[:verbose] = true
        options[:debug] = true
      end
  
      # This displays the help screen, all programs are
      # assumed to have this option.
      opts.on( '-?', '--help', 'Display this screen' ) do
        puts opts
        exit
      end
  
      opts.on_tail("--version", "Show version") do
          puts "#{opts.program_name} v.#{opts.version}, written by Nik Wolfgramm"
          puts
          puts "Copyright (C) 2009 Nik Wolfgramm"
          puts "This is free software; see the source for copying conditions."
          puts "There is NO warranty; not even for MERCHANTABILITY or"
          puts "FITNESS FOR A PARTICULAR PURPOSE."
          exit
        end
      end
  
      # get command passed
      command = ARGV[0]
      unless %w[backup restore optimize list-db list-bak].include? command
        puts "Please provide a valid action argument:"
        puts
        puts optparse.help
        exit
      end
  
      begin
        args = ARGV - [ARGV[0]]
        optparse.order(args)
        optparse.parse(args)
      rescue StandardError => message
        puts "Invalide option or missing argument: #{message}"
        puts
        puts optparse.help
        exit
      end
  
      if options[:debug]
        options.each {|key, value| puts "#{key}: #{value.to_s || 'nil'}" }
        exit
      end
  
      if connection[:password] == ''
        puts "Please provide at least a password for \"#{connection[:user]}\" (MySQL user)"
        puts
        puts optparse.help
        exit
      end
    end

  end # class
end # module
