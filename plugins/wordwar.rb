class Rogare::Plugins::Wordwar
  include Cinch::Plugin

  match /(wordwar|war|ww)\s*(.*)/
  @@usage = [
      'Use: !wordwar in [time before it starts (in minutes)] for [duration]',
      'Or:  !wordwar at [wall time e.g. 12:35] for [duration]',
      'Or even (defaulting to a 20 minute run): !wordwar at/in [time]',
      'And then everyone should: !wordwar join [username / wordwar ID]',
      'Also say !wordwar alone to get a list of current/scheduled ones.'
  ]

  @@redis = Redis.new

  def execute(m, cat, param)
    param = param.strip
    if param =~ /^(help|\?|how|what|--help|-h)/
      @@usage.each {|l| m.reply l}
      return
    end

    if param.empty?
      all_wars
      .reject {|w| w[:end] < Time.now}
      .sort_by {|w| w[:start]}
      .each do |war|
        togo, neg = dur_display war[:start]
        dur, _ = dur_display war[:end], war[:start]

        m.reply [
          # Insert a zero-width space as the second character of the nick
          # so that it doesn't notify that user. People using web clients
          # or desktop clients shouldn't see anything, people with terminal
          # clients may see a space, and people with bad clients may see a
          # weird box or invalid char thing.
          "#{war[:id]}: #{war[:owner].sub(/^(.)/, "\\1\u200B")}'s war",
          if neg
            "started #{togo} ago"
          else
            "starting in #{togo}"
          end,
          "for #{dur}"
        ].join(', ')
      end
      return
    end

    time, durstr = param.split('for').map {|p| p.strip}

    time = time.sub(/^at/).strip if time.start_with? 'at'
    durstr = "20 minutes" if durstr.nil? || durstr.empty?

    timeat = Chronic.parse(time)
    timeat = Chronic.parse("in #{time}") if timeat.nil?
    if timeat.nil?
      m.reply "Can't parse time: #{time}"
      return
    end

    duration = ChronicDuration.parse("#{durstr} minutes")
    if duration.nil?
      m.reply "Can't parse duration: #{durstr}"
      return
    end

    m.reply "Time: #{timeat}, Duration: #{duration}"

    store_war(m.user.nick, timeat, duration)
    m.reply "Stored"
  end

  def dur_display(time, now = Time.now)
    diff = time - now
    minutes = diff / 60.0
    secs = (minutes - minutes.to_i).abs * 60.0

    neg = false
    if minutes < 0
      minutes = minutes.abs
      neg = true
    end

    [if minutes > 5
      "#{minutes.round}m"
    elsif minutes > 1
      "#{minutes.floor}m #{secs.round}s"
    else
      "#{secs.round}s"
    end, neg]
  end

  def rk(war, sub = nil)
    ['wordwar', war, sub].compact.join ':'
  end

  def all_wars
    @@redis.keys(rk('*', 'start')).map do |k|
      k.gsub /(^wordwar:|:start$)/, ''
    end.map do |k|
      {
        id: k,
        owner: @@redis.get(rk(k, 'owner')),
        members: @@redis.smembers(rk(k, 'members')),
        start: Chronic.parse(@@redis.get(rk(k, 'start'))),
        end: Chronic.parse(@@redis.get(rk(k, 'end'))),
      }
    end
  end

  def store_war(user, time, duration)
    k = @@redis.incr rk('count')
    ex = ((time + duration + 5) - Time.now).to_i # Expire 5 seconds after it ends

    #@@redis.multi do
      @@redis.set rk(k, 'owner'), user, ex: ex
      @@redis.sadd rk(k, 'members'), user
      @@redis.expire rk(k, 'members'), ex
      @@redis.set rk(k, 'start'), "#{time}", ex: ex
      @@redis.set rk(k, 'end'), "#{time + duration}", ex: ex
    #end
  end
end