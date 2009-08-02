module SimpleMail
  # smtp for sending mails
  require 'net/smtp'

  def send_email(from, from_alias, to, to_alias, subject, message)
    msg = <<END_OF_MESSAGE
From: #{from_alias} <#{from}>
To: #{to_alias} <#{to}>
Subject: #{subject}

#{message}
END_OF_MESSAGE

    Net::SMTP.start('localhost') do |smtp|
      smtp.send_message msg, from, to
    end
  end
end

module DateFormat
  def fduration(duration)
    seconds = duration % 60
    duration = (duration - seconds) / 60
    minutes = duration % 60
    duration = (duration - minutes) / 60
    hours = duration % 24
    sprintf("%02d:%02d:%02d", hours, minutes, seconds)
 end
end

module FileSize
  def fsize(size)
    entities = %w[Bytes KB MB GB TB]
    entity = entities.first
    while size > 1024 && entity != entities.last
       size = size / 1024
       entity = entities[entities.index(entity) + 1]
    end 
    sprintf("%.1f %s", size, entity)
  end
end
