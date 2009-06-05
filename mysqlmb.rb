#!/usr/bin/env ruby

require 'lib/mysqlmaint'
require 'lib/simplemail'
require 'optparse'
require 'date'

include MySQLMaint
include SimpleMail

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
  opts.banner = "Usage: mysql-maintenance.rb [options]"
  opts.program_name = "MySQL Maintenance Buddy"

  # Define the options, and what they do
  options[:verbose] = false
  opts.on( '-v', '--verbose', 'Output more information' ) do
    options[:verbose] = true
  end

  options[:databases] = []
  opts.on( '-d', '--databases [db1,db2,db3]', Array, 'Define which databases to backup: database1,database2 ... (default: all databases)' ) do |db|
    options[:databases] = db
  end

  options[:backup] = true
  opts.on( '-b', '--no-backup', 'Disable database backups' ) do
    options[:backup] = false
  end

  options[:optimize] = true
  opts.on( '-o', '--no-optimize', 'Disable database optimization' ) do
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

  options[:backup_path] = 'backups'
  opts.on( '--backup-path [PATH]', 'backup storage directory (default: backups)' ) do |backup_path|
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
end

if ARGV.empty? || options[:password].empty?
  puts "Please provide at least a password for #{options[:user]} (MySQL user)\nSee usage for more details:"
  puts optparse.summarize
  exit
end

optparse.parse!

if options[:config]
  optparse.load(options[:config])
  unless File.exists(options[:config])
    puts "Abort: No configuration file found!\nSee config/config.rb.orig for an example."
    exit
  end
end
options[:credentials] = "--user=#{options[:user]} --password=#{options[:password]}"

MySQLMaint.credentials = options[:credentials]
MySQLMaint.mysql_path = options[:mysql_path]
MySQLMaint.backup_path = options[:backup_path]
MySQLMaint.host = options[:host]
MySQLMaint.verbose = options[:verbose]

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
  backup_error = MySQLMaint.db_backup(options[:databases])
  if backup_error == 0
    mail_message += "All databases successfully backed up\n"
  else
    mail_message += "Backup of MySQL failed for #{backup_error} database(s)\n"
  end
  # calculate size of all backups
  backup_size = MySQLMaint.backup_size
  mail_message += "Backup file size after compression: #{backup_size}"
end

if backup_error == false && options[:retention] > 0
  cleanup = MySQLMaint.delete_old_backups(options[:retention])
  cleanup = "no backups deleted" if cleanup.empty?
  mail_message += "Old backups removed: \n#{cleanup}\n"
end

if options[:optimize]
  MySQLMaint.chkdb()
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
