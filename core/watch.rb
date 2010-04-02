
miquire :plugin, 'plugin'
miquire :core, 'post'
miquire :core, 'utils'
miquire :core, 'environment'
miquire :core, 'userconfig'

require 'singleton'

class Watch
  include Singleton

  def self.scan_and_yield(handler)
    lambda {|this, name, post, messages, options|
      mumbles = this.get_posts(handler, messages, options)
      yield(name, post, mumbles) if mumbles
    }
  end

  def self.scan_and_fire(handler)
    self.scan_and_yield(handler){ |name, post, messages|
      Plugin::Ring.reserve(name, messages.map{ |m| [post, m] }) if messages
    }
  end

  @@events = {
    :period => {
      :interval => 1,
      :proc => lambda {|this, name, post, messages|
        unless messages then
          Plugin::Ring.reserve(name, [post])
        end
      }
    },
    :update => {
      :proc => Watch.scan_and_yield(:friends_timeline){ |name, post, messages|
        alist = messages.map{|m| [post, m] }
        me = post.user
        Plugin::Ring.reserve(:update, alist)
        Plugin::Ring.reserve(:mention, alist.select{ |m| m[1].receiver == me })
      }
    },
    :mention => {
      :proc => Watch.scan_and_yield(:replies){ |name, post, messages|
        alist = messages.map{|m| [post, m] }
        Plugin::Ring.reserve(:mention, alist)
        Plugin::Ring.reserve(:update, alist)
      }
    },
    :followed => {
      :proc => Watch.scan_and_fire(:followers)
    },
  }

  def events
    @@events[:update][:interval] = UserConfig[:retrieve_interval_friendtl]
    @@events[:update][:options] = {:count => UserConfig[:retrieve_count_friendtl]}

    @@events[:mention][:interval] = UserConfig[:retrieve_interval_mention]
    @@events[:mention][:options] = {:count => UserConfig[:retrieve_count_mention]}

    @@events[:followed][:interval] = UserConfig[:retrieve_interval_followed]
    @@events[:followed][:options] = {:count => UserConfig[:retrieve_count_followed]}

    return @@events
  end

  def initialize()
    super()
    @counter = 0
    @post = Post.new
    notice "start user @#{@post.user}"
    Plugin::Ring.fire(:boot, [@post])
    Plugin::Ring.go
  end

  def action(messages=nil)
    self.events.each{ |name, event|
      if not(Plugin::Ring.avail_plugins(name).empty?) then
        if((@counter % event[:interval]) == 0) then
          event[:proc].call(self, name, @post, messages, event[:options])
        end
      end
    }
    Plugin::Ring.go
    @counter += 1
  end

  def get_posts(api, message=nil, options={})
    if message then
      messages = [message]
    else
      messages = @post.scan(api, options)
    end
    return messages
  end

end