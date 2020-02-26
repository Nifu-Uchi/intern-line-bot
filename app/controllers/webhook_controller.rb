require 'line/bot'
require 'net/http'
require 'json'
class WebhookController < ApplicationController
  protect_from_forgery except: [:callback] # CSRF対策無効化

  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  def test
    testtext = 's'
    testtext = ENV["REMO_KEY"]
    return testtext
  end

  def getaction
    remoanser = 'N'
    key = ENV["REMO_KEY"]
    uri = URI.parse('https://api.nature.global/1/users/me')
    req = Net::HTTP::Get.new(uri.request_uri)
    req["Authorization"] = 'Bearer '+key
    req["Accept"] = 'application/json'
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true
    res = https.request(req)
    hash = JSON.parse(res.body)
    return hash['nickname']
  end
  def callback
    body = request.body.read

    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      head 470
    end

    events = client.parse_events_from(body)
    events.each { |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          
          message = {
            type: 'text',
            text: getaction
          }
          client.reply_message(event['replyToken'], message)
        when Line::Bot::Event::MessageType::Image, Line::Bot::Event::MessageType::Video
          response = client.get_message_content(event.message['id'])
          tf = Tempfile.open("content")
          tf.write(response.body)
        end
      end
    }
    head :ok
  end
end
