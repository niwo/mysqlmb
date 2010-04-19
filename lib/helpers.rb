module MySqlMb
  module SimpleMail
    # smtp for sending mails
    require 'net/smtp'

    def self.send_email(from, from_alias, to, to_alias, subject, message)
      msg = <<-END_OF_MESSAGE
        From: #{from_alias} <#{from}>
        To: #{to_alias} <#{to}>
        MIME-Version: 1.0
        Content-type: text/plain
        Subject: #{subject}
      END_OF_MESSAGE
      message.gsub!(/\n/,"\r\n")
      msg += message

      Net::SMTP.start('localhost') do |smtp|
        smtp.send_message msg, from, to
      end
    end
  end

  module Text
    MSG_TYPES = [:info, :error, :done]
    
    def self.fduration(duration)
      seconds = duration % 60
      duration = (duration - seconds) / 60
      minutes = duration % 60
      duration = (duration - minutes) / 60
      hours = duration % 24
      sprintf("%02d:%02d:%02d", hours, minutes, seconds)
    end

    def self.fsize(size)
      entities = %w[Bytes KB MB GB TB]
      entity = entities.first
      while size > 1024 && entity != entities.last
         size = size / 1024
         entity = entities[entities.index(entity) + 1]
      end 
      sprintf("%.1f %s", size, entity)
    end
    
    def self.colorize(text, color_code)
      "\033[0;#{color_code}#{text}\033[1;0m"
    end
    
    def self.tty_msg(msg, type = :info, width = 60)
      if type == :info || !MSG_TYPES.include?(type)
        return fixed_width(msg, width)
      end
      return done_msg(fixed_width(msg, width)) if type == :done
      return error_msg(fixed_width(msg, width)) if type == :error
    end
    
    def self.fixed_width(text, width = 60)
      f_text = text
      if text.size > width
        for i in 1..text.size do
          f_text.insert(i, "\n") if ((i % width) == 0)
          c =+ 1
        end
      end
      text = f_text
      f_text = ''
      text.each_line do |line|
        line.lstrip!
        while line.size < width
          line.insert(-1, ' ')
        end
        f_text << line
      end
      f_text
    end
    
    def self.done_msg(msg)
      green("#{msg}\t[DONE]")
    end
    
    def self.error_msg(msg)
      red("#{msg}\t[ERROR]")
    end
    
    def self.red(text)
      colorize(text, "031m")
    end
    
    def self.green(text)
      colorize(text, "032m")
    end
    
    def self.blue(text)
      colorize(text, "034m")
    end
  end
end
