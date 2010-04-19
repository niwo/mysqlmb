#!/usr/bin/env ruby
  
require 'optparse'
require 'date'
require 'yaml'
  
module MySqlMb
  class Parser
    # all commands
    CMD = %w[backup restore optimize cleanup list help]
 
    # commands which require no MySQL user/password
    NO_CREDENTIALS = { 'list' => {:list_type => :backup},
                       'cleanup' => {},
                       'help' => {} }

    def initialize
      @connection  = {}
      @paths       = {}
      @options     = {} 
      config_file  = File.join(File.dirname(__FILE__), *%w[.. config mysqlmb.yml])
      @config_file = config_file if File.exists? config_file 
    end
  
    def parse(command, args)
      optp = optparse(command, args)
      load_configfile() if @config_file
      set_defaults() 
      list_options if @options[:debug]
      verify_input(optp, command)
      return @connection, @paths, @options
    end
    
    private
 
    def list_options
      puts "Database Connection:"
      @connection.each do |key, value|
        if key == :password
          value = value.empty? ? '<no password>' : '********'
        end
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
 
    def load_configfile(file = @config_file)
       file_options = YAML.load_file(file)
       # does the file contain any options?
       if file_options 
         file_options.each do |key, value|
           # connection values
           if [:host, :user, :password].include? key
             @connection[key] ||= value
           # path values
           elsif [:backup_path, :mysql_path, :mysqldump_path, :mysqlcheck_path].include? key
             key = key.to_s.gsub('_path', '').to_sym
             @paths[key] ||= value
           else
             @options[key] ||= value
           end
         end
       end
    end
    
    def set_defaults
      # default connetion
      @connection[:user]        ||= 'backup'
      @connection[:password]    ||= ''
      
      # default paths
      @paths[:logfile]          ||= File.join(File.dirname(__FILE__), *%w[.. log mysqlmb.log])
      @paths[:backup]           ||= File.join(File.dirname(__FILE__), *%w[.. backups])
      @paths[:mysql]            ||= '/usr/bin/mysql'
      @paths[:mysqldump]        ||= '/usr/bin/mysqldump'
      @paths[:mysqlcheck]       ||= '/usr/bin/mysqlcheck'
      
      # default options
      @options[:databases]      ||= []
      @options[:retention]      ||= 30
      @options[:restore_offset] ||= -1
      @options[:mail_to]        ||= ''
      @options[:list_type]      ||= :mysql
      @options[:date_format]    ||= "%Y-%m-%d"
      @options[:debug]            = false  if @options[:debug].nil?
      @options[:verbose]          = true  if @options[:verbose].nil?
      @options[:optimize]         = false  if @options[:optimize].nil?
      @options[:mail]             = @options[:mail].nil? ? false : true
      @options[:force]            = false  if @options[:force].nil?
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
      opts.version = "1.3"
      opts.summary_width = 30
      opts.summary_indent = "  "
      opts.separator ""
      opts.separator "List of Commands:"
      opts.separator "  backup \t\t\t Backup databases"
      opts.separator "  restore \t\t\t Restore databases"
      opts.separator "  optimize \t\t\t Optimize databases"
      opts.separator "  cleanup \t\t\t Cleanup old database backups"
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
        @options[:databases] = db
      end
 
      opts.on( '--[no-]optimize', 'Disable database optimization' ) do |o|
        @options[:optimize] = o
      end
 
      opts.on( '-r', '--retention-time DAYS', Integer, 'How many days to keep the db backups (default: 30 days)' ) do |days|
        @options[:retention] = days
      end
 
      opts.on( '-t', '--time-offset DAYS', Integer, 'How old are the backups to restore (default: -1 (yesterday))' ) do |days|
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
      
      opts.on( '-c', '--config-file FILE', 'Specify a configuration file which contains default options',                                          'see config/config.rb.orig for an example' ) do |file|
        if File.exists? file
          @config_file = file
        else
	  puts "Abort: No configuration file found!\nSee #{APP_PATH}/config/mysqlmb.conf.dist for an example."
        end
      end
      
      opts.on( '-q', '--quite', 'Surpress program output' ) do
        @options[:verbose] = false
      end
 
      opts.on( '-f', '--force', 'Force backup file deletion' ) do
        @options[:force] = true
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
