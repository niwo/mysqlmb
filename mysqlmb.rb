#!/usr/bin/env ruby

# resolve the application path
if File.symlink?(__FILE__)
  APP_PATH = File.dirname(File.readlink(__FILE__))
else
  APP_PATH = File.dirname(__FILE__)
end

require APP_PATH + "/lib/mysqlmaint"
require APP_PATH + "/lib/simplemail"
require 'optparse'
require 'date'
require 'yaml'
include SimpleMail

LOGFILE = APP_PATH + "/log/mysqlmb.log"

def fduration(duration)
  seconds = duration % 60
  duration = (duration - seconds) / 60
  minutes = duration % 60
  duration = (duration - minutes) / 60
  hours = duration % 24
  "#{hours.to_i}:#{minutes.to_i}:#{seconds.to_i}"
end

# Options Parser
options = {}
optparse = OptionParser.new do|opts|
  # Set a banner, displayed at the top
  # of the help screen.
  opts.banner = "Usage: mysqlmb.rb [options]"
  opts.program_name = "MySQL Maintenance Buddy"
  opts.version = "1.0"

  # Define the options, and what they do
  options[:verbose] = false
  opts.on( '-v', '--verbose', 'Output more information' ) do
    options[:verbose] = true
  end

  options[:databases] = []
  opts.on( '-d', '--databases db1,db2,db3', Array, 'Define which databases to backup: database1,database2 ... (default: all databases)' ) do |db|
    options[:databases] = db
  end

  options[:backup] = true
  opts.on( '--no-backup', 'Disable database backups' ) do
    options[:backup] = false
  end

  options[:optimize] = true
  opts.on( '--no-optimize', 'Disable database optimization' ) do
    options[:optimize] = false
  end

  options[:retention] = 30
  opts.on( '-r', '--retention-time [DAYS]', Integer, 'How many days to keep the db backups (default: 30 days)' ) do |days|
    options[:retention] = days
  end

  options[:host] = 'localhost'
  opts.on( '-h', '--host [HOST]', 'MySQL hostname (default: localhost)' ) do |host|
    options[:host] = host
  end

  options[:user] = 'backup'
  opts.on( '-u', '--user [USER]', 'MySQL backup user (default: backup)' ) do |user|
    options[:user] = user
  end

  options[:password] = ''
  opts.on( '-p', '--password PASSWORD', 'MySQL password' ) do |password|
    options[:password] = password
  end

  options[:mail_to] = ''
  opts.on( '-m', '--mail-to [MAIL-ADDRESS]', 'email address to send reports to, if not specified no mails will be sent' ) do |mail|
    options[:mail] = mail
  end

  options[:backup_path] =  File.expand_path(APP_PATH, '/backups')
  opts.on( '--backup-path [PATH]', "backup storage directory (default: #{options[:backup_path]})" ) do |backup_path|
    options[:backup_path] = backup_path
  end

  options[:mysql_path] = '/usr/bin/'
  opts.on( '--mysql-path [PATH]', 'Specify the MySQL utility path (default: /usr/bin/)' ) do |mysql_path|
    options[:mysql_path] = mysql_path
  end

  options[:config] = nil
  opts.on( '-c', '--config-file [FILE]', 'Specify a configuration file which contains all options (see config/config.rb.orig for an example)' ) do |file|
    options[:config] = file
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

begin
  optparse.parse!
rescue OptionParser::InvalidOption
   puts "Invalide option provided."
   puts optparse.help
  exit
end

if options[:config]
  unless File.exists?(options[:config])
    puts "Abort: No configuration file found!\nSee #{APP_PATH}/config/mysqlmb.conf.orig for an example."
    exit
  end
  options = options.merge!(YAML.load_file(options[:config]))
  options.each {|key, value| puts "#{key}: #{value || 'nil'}" } if options[:verbose]
end

if options[:password] == ''
  puts "Please provide at least a password for #{options[:user]} (MySQL user)\nSee usage for more details:"
  puts optparse.help
  exit
end

mysqlmaint = MySQLMaint.new(options[:user],
			options[:password],
			options[:host],
			options[:backup_path],
			options[:mysql_path],
 			LOGFILE,
			options[:verbose]
)

# 
# execute the maintenance procedure
#

backup_error = 0
start_time = Time::now
DATE = start_time.strftime("%d-%m-%Y")

mail_message = <<END
----------------------------------------------------------
                MySQL maintenance on #{options[:host]}
                #{DATE}
----------------------------------------------------------
Settings: 
  #{options[:retention]} days backup retention time
  Backup enabled: #{options[:backup]}
  Database optimization enabled: #{options[:optimize]}
----------
END

if options[:backup]
  backup_error, message = mysqlmaint.db_backup(options[:databases])
  if backup_error == 0
    mail_message += "All databases successfully backed up: #{message}\n"
  else
    mail_message += "Backup of MySQL failed: #{message}\n"
  end
  # calculate size of all backups
  backup_size = mysqlmaint.backup_size
  mail_message += "Backup file size after compression: #{backup_size}\n"
end

if backup_error == 0 && options[:retention] > 0
  cleanup = mysqlmaint.delete_old_backups(options[:retention])
  cleanup = "no backups deleted" if cleanup.empty?
  mail_message += "Old backups removed: \n#{cleanup}\n"
end

if options[:optimize]
  mysqlmaint.chkdb()
  mail_message += "All databases have been optimized with mysqlcheck\n"
end

execution_time = (Time.now - start_time)
mail_message += "----------\nMaintenance duration: #{fduration(execution_time)}\n"

# send confirmation email
unless options[:mail_to].empty?
  mail_subject = "MySQL Maintenence"
  backup_error != 0 ? mail_subject += " - failed" :  mail_subject += " - successful"
  SimpleMail.send_email("mysql@#{options[:host]}", "", options[:mail_to], "", mail_subject, mail_message)
end
