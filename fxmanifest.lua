fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vi_radio'
author 'sej0bec (original GTA V mod) / FiveM port'
description 'GTA VI inspired radio HUD, mute system and slow-motion radio wheel'
version '1.0.0'

shared_script 'config.lua'
client_script 'client.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/fonts/Anton.ttf',
    'html/logos/*.png',
    'html/icons/*.png',
    'html/sfx/*.wav',
}
