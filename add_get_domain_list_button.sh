#!/bin/sh

# Скрипт для добавления кнопки ручного обновления доменов в LuCI
# Сохраните как add_button.sh, затем выполните: sh add_button.sh

# 1. Создаём структуру каталогов
mkdir -p /usr/lib/lua/luci/controller/mybutton
mkdir -p /usr/lib/lua/luci/view/mybutton

# 2. Создаём контроллер
cat << 'EOF' > /usr/lib/lua/luci/controller/mybutton/update.lua
module("luci.controller.mybutton.update", package.seeall)

function index()
    entry({"admin", "services", "update_domains"}, call("action_update"), _("Обновить домены"), 90)
end

function action_update()
    luci.http.prepare_content("text/plain")
    luci.sys.call("/etc/init.d/getdomains start >/dev/null 2>&1")
    luci.http.write("Список доменов обновлён!")
end
EOF

# 3. Создаём HTML-шаблон
cat << 'EOF' > /usr/lib/lua/luci/view/mybutton/update.htm
<%+header%>
<div class="cbi-map">
    <h2>Ручное обновление доменов</h2>
    <div class="cbi-section">
        <input type="button" class="cbi-button cbi-button-apply" value="Обновить сейчас" 
            onclick="XHR.get('<%=luci.dispatcher.build_url('admin/services/update_domains')%>', null, 
            function(){ window.alert('Обновление запущено') })" />
    </div>
</div>
<%+footer%>
EOF

# 4. Чистим кеш интерфейса
rm -f /tmp/luci-indexcache 2>/dev/null

# 5. Устанавливаем права
chmod 644 /usr/lib/lua/luci/controller/mybutton/update.lua
chmod 644 /usr/lib/lua/luci/view/mybutton/update.htm

echo "Готово! Перезагрузите страницу LuCI → Сервисы → Обновить домены"