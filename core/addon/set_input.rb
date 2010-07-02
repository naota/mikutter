# -*- coding:utf-8 -*-
miquire :addon, 'addon'
miquire :core, 'config'
miquire :addon, 'settings'

Module.new do

  shrink_url = Mtk.group('短縮URL', Mtk.boolean(:shrinkurl_always, '常にURLを短縮する'))
  container = Gtk::VBox.new(false, 8).
    closeup(Mtk.keyconfig('つぶやきを投稿するキー', :mumble_post_key)).
    closeup(Mtk.adjustment('投稿をリトライする回数', :message_retry_limit, 1, 99)).
    closeup(shrink_url).
    closeup(Mtk.group('フッタ',
                      Mtk.input(:footer, 'デフォルトで挿入するフッタ'),
                      Mtk.boolean(:footer_exclude_reply, 'リプライの場合はフッタを付与しない'),
                      Mtk.boolean(:footer_exclude_retweet, '引用(非公式ReTweet)の場合はフッタを付与しない')))

  plugin = Plugin::create(:set_input)

  plugin.add_event(:boot){ |service|
    Plugin.call(:setting_tab_regist, container, '入力') }

  plugin.add_event(:regist_url_shrinker_setting){ |label, *widgets|
    shrink_url.child.add(Mtk.expander(label, false, *widgets)).show_all }

end

#Plugin::Ring.push Addon::SetInput.new,[:boot, :plugincall]
