# -*- coding: utf-8 -*-

miquire :addon, 'addon'
miquire :mui, 'skin'
miquire :mui, 'timeline'

Module.new do
  main = Gtk::TimeLine.new()

  plugin = Plugin::create(:friend_timeline)
  plugin.add_event(:boot){ |service|
    Plugin.call(:mui_tab_regist, main, 'Home Timeline', MUI::Skin.get("timeline.png")) }
  plugin.add_event(:update){ |service, messages|
    main.add(messages) }

end
