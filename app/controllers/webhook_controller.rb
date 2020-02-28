require 'line/bot'
require 'net/http'
require 'json'
require 'bigdecimal'
class WebhookController < ApplicationController
  protect_from_forgery except: [:callback] # CSRF対策無効化
  APPLIANCE_ID_LIST = {'リビング'=>ENV["LIVINGLIGHT_ID"],'寝室'=>ENV["BROOMLIGHT_ID"],'エアコン'=>ENV["AIRCON_ID"],'テレビ'=>ENV["TV_ID"]}
  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  def message_convert(msg)
    puts('User:'+msg)
    result = msg.split("、")
    buttonlist = {"オン"=>'on','オフ'=>'off'}
    result[1] = buttonlist[result[1]]
    if result[1].nil? then
      result[1] = 'N'
    end
    return result
  end
  

  def call_api(appliance,order)
    case appliance
    when '気温は？'
      action_response = ("今の室温は" + gettemp.to_s + "度くらいにゃ.")
    when '寒くない？'
      nowtemp =gettemp.to_f
      if nowtemp > 14 then
        action_response = ('今は' + nowtemp.to_s + "度で，寒くはないよー．\nありがとね.")
      else 
        action_response = ('今は' + nowtemp.to_s + "度で,ちょっと寒いかも..暖房つけてよ.")
      end
    when '家をチェックして！'
      answerset = get_appliances_status
      temp = gettemp.to_s
      action_response = "...はーーーーい.\nえーっと...\nいまの室温は" + temp + "度\n"+
                        'リビングの電気は' + answerset['livingroomlight_state'] + "になってて,\n" +
                        '寝室の電気は' + answerset['bedroomlight_state'] + "\n" +
                        'あと，エアコンは' + answerset['aircon_state'] + "かなぁ.\n"+
                        "もう二度とやらせないでほしいにゃ."
    when 'リビング','寝室'
      action_response = light(appliance,order)
    when '電気全部つけて'
      light('リビング','on')
      light('寝室','on')
      action_response = '全部つけたよ.'
    when '電気全部消して'
      light('リビング','off')
      light('寝室','off')
      action_response = '全部消したよ.'
    when 'みんなを起こして！'
      light('リビング','on')
      light('寝室','on')
      tv('テレビ','on')
      aircon('エアコン','on')
      action_response = '全部つけた！！！みんな起きてにゃ.'
    when '節約してよ'
      light('リビング','off')
      light('寝室','off')
      aircon('エアコン','オフ')
      action_response = 'はーい...全部消しましたニャ...'
    when 'エアコン'
      action_response = aircon(appliance,order)
    when 'テレビ'
      action_response = tv(appliance,order)
    else
      err_respon = ['なに？','今寝てるからさ...','おやつの話？','靴下かじっていい？','さっきおやつ箱開けちゃった...']

      action_response = err_respon.sample
    end
    return action_response
  end

##家電操作関数（POST）
  def aircon(appliance,button)
    if button=='N' then
      return '何を押せばいいの？'
    elsif button == 'on'
      aircon_button = ''
    elsif button = 'off'
      aircon_button = 'power-off'
    end
    appliance_id = APPLIANCE_ID_LIST[appliance]
    if appliance_id.nil? then
      return 'どれを動かせばいいかわからなくなっちゃった'
    end
    url = 'https://api.nature.global/1/appliances/'+appliance_id+'/aircon_settings?button='+aircon_button
    summary = apipost(url)
    responsemsg = 'エアコンを'+button+'にしたよ'
    return responsemsg
  end

  def light(appliance,button)
    if button=='N' then
      return '何を押せばいいの？'
    end
    appliance_id = APPLIANCE_ID_LIST[appliance]
    if appliance_id.nil? then
      return 'どれを動かせばいいかわからなくなっちゃった.'
    end
    url = 'https://api.nature.global/1/appliances/'+appliance_id+'/light?button='+button
    summary = apipost(url)
    responsemsg = appliance+'ライトを'+button+'にしたよ.'
  end
  def tv(appliance,button)
    if button=='N' then
      return '何を押せばいいの？'
    end
    appliance_id = APPLIANCE_ID_LIST[appliance]
    puts(appliance)
    puts(APPLIANCE_ID_LIST)
    puts(ENV)
    if appliance_id.nil? then
      return 'どれを動かせばいいかわからなくなっちゃった.'
    end
    url = 'https://api.nature.global/1/appliances/'+appliance_id+'/tv?button=power'##テレビはON/OFF区別がない
    summary = tvpost(url)
    responsemsg = 'テレビの電源ボタンを押しといたよ.'
  end

##状態取得関数（GET)
  def gettemp #気温取る
    hash = apiget('https://api.nature.global/1/devices')
    tempr = hash.dig(0,'newest_events','te','val')
    answer = tempr.to_f.round(3).to_s
    return answer
  end

  def get_appliances_status
    hash = apiget('https://api.nature.global/1/appliances')
    state_convert = {'on': 'つけっぱ','off': 'きえてる','power-off': 'きえてる','': 'ついてる'}
    appliance_state ={}
    appliance_state['bedroomlight_state'] = hash.dig(0,'light','state','power')
    appliance_state['livingroomlight_state'] = hash.dig(2,'light','state','power')
    if (hash.dig(1,'settings','button')) == 'power-off' then
      appliance_state['aircon_state'] = 'たぶんついてる'
    else
      appliance_state['aircon_state'] = '消えてる'
    end
    return appliance_state
  end

##api get/post
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
  def tvpost(url)
    
    key = ENV["REMO_KEY"]
    uri = URI.parse(url)
    puts(uri)
    req = Net::HTTP::Post.new(uri.request_uri)
    req["Content-Type"] = 'application/x-www-form-urlencoded'
    req["Authorization"] = 'Bearer '+key
    req["Accept"] = 'application/json'
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true
    res = https.request(req)
    hash = JSON.parse(res.body)
    return hash
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
          appliance,order = message_convert(event.message['text'])
          cat_response = call_api(appliance,order)
          puts (cat_response)
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
