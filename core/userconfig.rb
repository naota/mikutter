# -*- coding: utf-8 -*-

require File.expand_path('utils')
miquire :core, 'configloader'

require 'singleton'
require 'fileutils'
require 'gtk2'

#
#= UserConfig 動的な設定
#
#プログラムから動的に変更される設定。
#プラグインの設定ではないので注意。
class UserConfig
  include Singleton
  include ConfigLoader
  extend MonitorMixin
  #
  # 予約された設定一覧
  #

  @@defaults = {
    :retrieve_interval_friendtl => 1,   # TLを更新する間隔(int)
    :retrieve_interval_mention => 20,   # Replyを更新する間隔(int)
    :retrieve_interval_search => 60,    # 検索を更新する間隔(int)
    :retrieve_interval_followings => 60,  # followを更新する間隔(int)
    :retrieve_interval_followers => 60,  # followerを更新する間隔(int)

    :retrieve_count_friendtl => 20,   # TLを取得する数(int)
    :retrieve_count_mention => 20,    # Replyを取得する数(int)
    :retrieve_count_followings => 20,   # followを取得する数(int)
    :retrieve_count_followers => 20,   # followerを取得する数(int)

    # User Stream
    :realtime_rewind => true,

    # デフォルトのフッダ
    :footer => "",

    # リプライ元を常に取得する
    :retrieve_force_mumbleparent => true,

    # 遅延対策
    :anti_retrieve_fail => false,

    # つぶやきを投稿するキー
    :shortcutkey_keybinds => {1 => {:key => "Control + Return", :name => '投稿する', :slug => :post_it}},

    # リクエストをリトライする回数
    :message_retry_limit => 10,

    # 通知を表示しておく秒数
    :notify_expire_time => 10,

    :retweeted_by_anyone_show_timeline => true,

    :retweeted_by_anyone_age => true,

    :favorited_by_anyone_show_timeline => true,

    :favorited_by_anyone_age => true,

    # タブの並び順
    :tab_order => [['Home Timeline', 'Replies', 'Search', 'Settings']],

    # タブの位置 [上,下,左,右]
    :tab_position => 3,

    # 常にURLを短縮して投稿
    :shrinkurl_always => true,

    # 常にURLを展開して表示
    :shrinkurl_expand => true,

    # 非公式RTにin_reply_to_statusをつける
    :legacy_retweet_act_as_reply => false,

    :biyly_user => '',
    :bitly_apikey => '',

    :mumble_basic_font => 'Sans 10',
    :mumble_basic_color => [0, 0, 0],
    :mumble_reply_font => 'Sans 8',
    :mumble_reply_color => [255*0x66, 255*0x66, 255*0x66],

    :mumble_basic_bg => [65535, 65535, 65535],
    :mumble_reply_bg => [65535, 255*222, 255*222],
    :mumble_self_bg => [65535, 65535, 255*222],
    :mumble_selected_bg => [255*222, 255*222, 65535],

    # 右クリックメニューの並び順
    :mumble_contextmenu_order => ['copy_selected_region',
                                  'copy_description',
                                  'reply',
                                  'reply_all',
                                  'retweet',
                                  'delete_retweet',
                                  'legacy_retweet',
                                  'favorite',
                                  'delete_favorite',
                                  'delete']

  }

  @@watcher = Hash.new{ [] }
  @@watcher_id = Hash.new
  @@watcher_id_count = 0

  # 設定名 _key_ にたいする値を取り出す
  # 値が設定されていない場合、nilを返す。
  def self.[](key)
    UserConfig.instance.at(key, @@defaults[key.to_sym])
  end

  # 設定名 _key_ に値 _value_ を関連付ける
  def self.[]=(key, val)
    watchers = synchronize{
      if not(@@watcher[key].empty?)
        before_val = UserConfig.instance.at(key, @@defaults[key.to_sym])
        @@watcher[key].map{ |id|
          proc = if @@watcher_id.has_key?(id)
                   @@watcher_id[id]
                 else
                   @@watcher[key].delete(id)
                   nil end
          lambda{ proc.call(key, val, before_val, id) } if proc } end }
    if watchers.is_a? Enumerable
      watchers.each{ |w| w.call } end
    UserConfig.instance.store(key, val)
  end

  # 設定名 _key_ の値が変更されたときに、ブロック _watcher_ を呼び出す。
  # watcher_idを返す。
  def self.connect(key, &watcher)
    synchronize{
      id = @@watcher_id_count
      @@watcher_id_count += 1
      @@watcher[key] = @@watcher[key].push(id)
      @@watcher_id[id] = watcher
      id
    }
  end

  # watcher idが _id_ のwatcherを削除する。
  def self.disconnect(id)
    synchronize{
      @@watcher_id.delete(id)
    }
  end

end
