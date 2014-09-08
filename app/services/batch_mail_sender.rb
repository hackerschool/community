require 'uri'
require 'net/http'
require 'json'

# NOTE: This ignores HTML messages for the moment.
class BatchMailSender
  include EmailFields

  class Error < StandardError; end

  attr_reader :mail, :recipient_variables

  def initialize(mail, recipient_variables)
    @mail = mail
    @recipient_variables = recipient_variables
  end

  def deliver
    if ActionMailer::Base.delivery_method == :test
      ActionMailer::Base.deliveries << mail
    end

    if Rails.env.production?
      deliver_to_recipients
    end

    logger.info("\nSent batch message \"#{mail.subject}\"")
    logger.debug(mail.to_s)
  end

private
  def deliver_to_recipients
    url = URI("https://api:#{ENV["MAILGUN_API_KEY"]}@api.mailgun.net/v2/mail.community.hackerschool.com/messages")

    res = Net::HTTP.post_form(url,
      # TODO: These To fields need to match up with keys in recipient_variables,
      # which might not include display addresses.
      "to" => mail.to,
      "from" => mail["from"].to_s,
      "subject" => mail.subject,
      "text" => mail.text_part.body.to_s,
      "html" => mail.html_part.body.to_s,
      "h:Message-ID" => mail.header["Message-ID"].to_s,
      "h:Reply-To" => "#{list_post_field(reply_info)}, #{mail["from"].to_s}",
      "h:In-Reply-To" => mail.header["In-Reply-To"].to_s,
      "h:List-Post" => list_post_field("%recipient.reply_info%"),
      "h:List-ID" => list_id_field,
      "h:Precedence" => "list",
      "v:reply_info" => "%recipient.reply_info%",
      "recipient-variables" => JSON.generate(recipient_variables)
    )

    unless res.code == "200"
      raise Error, "Mailgun API returned response code: #{res.code}\n#{res.body}"
    end
  end

  def logger
    ActionMailer::Base.logger
  end
end
