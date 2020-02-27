require 'line/bot'
require 'net/http'
require 'json'
require 'bigdecimal'
class WebhookController < ApplicationController
  protect_from_forgery except: [:callback] # CSRF対策無効化

  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  def message_convert(msg)
    result = msg.split("、")
    buttonlist = {"オン"=>'on','オフ'=>'off'}
    result[1] = buttonlist[result[1]]
    return result
  end
  
#送られたメッセージの判定
  def call_api(appliance,order)

    case appliance
    when '気温は？' ,
      action_response = gettemp
    when '寒くない？'　 
      nowtemp =gettemp
      if nowtemp > 14 then
      end
    #エアコンのオンオフをしたときにgettempして，それに応じたメッセージを返す
    when 'リビング','寝室'
      action_response = light(appliance,order)
    when '全灯'
      light('リビング','on')
      light('寝室','on')
      action_response = '全部つけたよ'
    else
      action_response = 'ごめん，わからない...'
    end
    return action_response
  end
#送られたメッセージの判定ここまで############
def light(lightname,button)
  puts(button)
  #puts('ライト関数')
  #puts(lightname)
  if button=='N' then
    return '何を押せばいいの？'
  end
  appliance_id_list = {'リビング'=>ENV["LIVINGLIGHT_ID"],'寝室'=>ENV["BROOMLIGHT_ID"]}
  appliance_id = appliance_id_list.dig(lightname)
  if appliance_id.nil? then
    return 'どれを動かせばいいかわからなくなっちゃった'
  end
  url = 'https://api.nature.global/1/appliances/'+appliance_id+'/light?button='+button
  puts (url)
  summary = apipost(url)
  puts(summary)
  responsemsg = lightname+'ライトを'+button+'にしたよ'
  puts(responsemsg)
  return responsemsg
end
##API関数ここから############
  def apiget(url)
    key = ENV["REMO_KEY"]
    uri = URI.parse(url)
    req = Net::HTTP::Get.new(uri.request_uri)
    req["Authorization"] = 'Bearer '+key
    req["Accept"] = 'application/json'
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true
    res = https.request(req)
    hash = JSON.parse(res.body)
    return hash
  end

  def apipost(url)
    remoanser = 'N'
    key = ENV["REMO_KEY"]
    uri = URI.parse(url)
    puts(uri)
    req = Net::HTTP::Post.new(uri.request_uri)
    req["Authorization"] = 'Bearer '+key
    req["Accept"] = 'application/json'
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true
    res = https.request(req)
    hash = JSON.parse(res.body)
    
    return hash
  end

  def gettemp #気温取る
    hash = apiget('https://api.nature.global/1/devices')
    tempr = hash.dig(0,'newest_events','te','val')
    anser = ('現在の室温は' + tempr.to_f.round(3).to_s + '度だよ．')
    return anser
  end
##API関数ここまで############


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
          appliance,order = message_convert(event.message['text'])
          cat_response = call_api(appliance,order)
          message = {
            type: 'text',
            text: cat_response
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
