#!/usr/bin/env ruby
  
require 'optparse'
require 'date'
require 'yaml'
require 'lib/helpers'
include SimpleMail
include DateFormat
  
module MySqlMb
 
  class Parser
    # all commands
    CMD = %w[backup restore optimize list]
 
    # commands which require no MySQL user/password
    NO_CREDENTIALS = {'list' => {:list_type => :backup}}
 
    def initialize
      @connection = {}
      @paths = {}
      @options = {}
    end
  
    def parse(command, args)
      optp = optparse(command, args)
      set_defaults()
      list_options if @options[:debug]
      verify_input(optp, command)
      return @connection, @paths, @options, @databases
    end
    
    private
 
    def list_options
      puts "Connection:"
      @connection.each do |key, value|
        value.gsub!(/./) { |s| "*" } if key == :password
        puts "\t#{key}: #{value.to_s || 'nil'}"
      end
      puts "Paths:"
      @paths.each {|key, value| puts "\t#{key}: #{value.to_s || 'nil'}" }
      puts "Options:"
      @options.each {|key, value| puts "\t#{key}: #{value.to_s || 'nil'}" }
      exit
    end
 
    def verify_input(optp, command)
      if missing_credentials? command
        puts "Please provide at least a password for MySQL user \"#{@connection[:user]}\""
        puts
        puts optp.help
        return false 
      end
 
      unless @options[:version] || CMD.include?(command)
        puts "Please provide a valid action argument:"
        puts
        puts optp.help
        return false
      end
    end
 
    def load_configfile(file, force = false)
       file_options = YAML.load_file(file)
       file_options.each do |key, value|
         # connection values
         if [:host, :user, :password].include? key
           force ? @connection[key] = value : @connection[key] ||= value
         # path values
         elsif [:backup, :mysql, :mysqldump].include? key
           force ? @paths[key] = value : @paths[key] ||= value
         else
           force ? @options[key] = value : @options[key] ||= value
         end
       end
    end
    
    def set_defaults
      # default databases (all)
      @databases                ||= []
      
      # default connetion
      @connection[:user]        ||= 'backup'
      @connection[:password]    ||= ''
      
      # default paths
      @paths[:logfile]          ||= (APP_PATH + "/log/mysqlmb.log")
      @paths[:backup]           ||=  File.expand_path(APP_PATH, '/backups')
      @paths[:mysql]            ||= '/usr/bin/mysql'
      @paths[:mysqldump]        ||= '/usr/bin/mysqldump'
      @paths[:mysqlcheck]       ||= '/usr/bin/mysqlcheck'
      
      # default options
      @options[:optimize]       ||= true
      @options[:retention]      ||= 30
      @options[:restore_offset] ||= 1
      @options[:mail_to]        ||= ''
      @options[:mail]           ||= false
      @options[:list_type]      ||= :mysql
      @options[:date_format]    ||= "%Y-%m-%d"
      @options[:debug]          ||= false
      @options[:verbose] = false
    end
 
    def missing_credentials?(command)
      if (@connection[:user] == '' || @connection[:password] == '')
        if NO_CREDENTIALS.has_key?(command)
          return false if NO_CREDENTIALS[command].empty?
          @options.each {|key, value| return false if NO_CREDENTIALS[command][key] === value }
          return true
        end
        return true
      end
      false
    end
    
    def optparse(command, args)
      optparse = OptionParser.new do |opts|
      # Set a banner, displayed at the top
      # of the help screen.
      opts.banner = "Usage: mysqlmb COMMAND [options]"
      opts.program_name = "MySQL Maintenance Buddy"
      opts.version = "1.2"
      opts.summary_width = 30
      opts.summary_indent = "  "
      opts.separator ""
      opts.separator "List of Commands:"
      opts.separator "  backup \t\t\t Backup databases"
      opts.separator "  restore \t\t\t Restore databases"
      opts.separator "  optimize \t\t\t Optimize databases"
      opts.separator "  list \t\t\t\t List databases or backups"
      opts.separator ""
      opts.separator "Options:"
 
      # Define the options, and what they do
      opts.on( '-u', '--user USER', 'MySQL backup user (default: backup)' ) do |user|
        @connection[:user] = user
      end
 
      opts.on( '-p', '--password PASSWORD', 'MySQL password' ) do |password|
        @connection[:password] = password
      end
      
      opts.on( '-d', '--databases db1,db2,db3', Array, 'Define which databases to backup (default: all)',
                                                       'Syntax: database1,database2',
                                                       'Keywords: all, user, system') do |db|
        @databases = db
      end
 
      opts.on( '--[no-]optimize', 'Disable database optimization' ) do |o|
        @options[:optimize] = o
      end
 
      opts.on( '-r', '--retention-time DAYS', Integer, 'How many days to keep the db backups (default: 30 days)' ) do |days|
        @options[:retention] = days
      end
 
      opts.on( '-t', '--time-offset DAYS', Integer, 'How old are the backups to restore (default: 1 (yesterday))' ) do |days|
        @options[:restore_offset] = days
      end
 
      opts.on( '-m', '--mail-to MAIL-ADDRESS', 'email address to send reports to' ) do |mail|
        @options[:mail_to] = mail
      end
 
      opts.on( '--[no-]mail', 'activate/deactivate mail messages' ) do |mail|
        @options[:mail] = mail
      end
 
      opts.on( '-l', '--list-type TYPE', [:mysql, :backup], 'Select list type (mysql, backup)' ) do |type|
        @options[:list_type] = type
      end
 
      opts.on( '--backup-path PATH', "backup storage directory (default: #{@paths[:backup]})" ) do |backup_path|
        @paths[:backup] = backup_path
      end
 
      opts.on( '--mysql-path PATH', 'Specify the MySQL utility path (default: /usr/bin/)' ) do |mysql_path|
        @paths[:mysql] = mysql_path
      end
 
      opts.on( '--date-format FORMAT', 'Date format for backup file name (default: %Y-%m-%d)' ) do |format|
        @options[:date_format] = format
      end
      
      opts.on( '-c', '--config-file FILE', 'Specify a configuration file which contains all options',                                          'see config/config.rb.orig for an example' ) do |file|
        unless File.exists?(file)
          puts "Abort: No configuration file found!\nSee #{APP_PATH}/config/mysqlmb.conf.dist for an example."
          exit
        end
        @options[:config_file] = file
        load_configfile(file)
      end
      
      opts.on( '--verbose', 'Output more information' ) do
        @options[:verbose] = true
      end
 
      opts.on( '--debug', 'Debugging mode: show arguments passed' ) do
        @options[:verbose] = true
        @options[:debug] = true
      end
 
      # This displays the help screen, all programs are
      # assumed to have this option.
      opts.on( '-?', '--help', 'Display this screen' ) do
        puts opts
        return false
      end
 
      opts.on_tail( '--version', "Show version" ) do
          @options[:lala] = 'lulu'
          puts "#{opts.program_name} v.#{opts.version}, written by Nik Wolfgramm"
          puts
          puts "Copyright (C) 2009 Nik Wolfgramm"
          puts "This is free software; see the source for copying conditions."
          puts "There is NO warranty; not even for MERCHANTABILITY or"
          puts "FITNESS FOR A PARTICULAR PURPOSE."
          exit
        end
      end
      
      optparse.parse!(args)
      return optparse  
    end
 
  end # class
end # module