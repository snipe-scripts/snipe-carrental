fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Snipe Development'
description 'World-space capsule vehicle rental for Qbox'
version '1.0.0'

ui_page 'ui/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/world_dui_config.lua',
    'client/world_dui.lua',
    'client/props.lua',
    'client/capsule.lua',
    'client/placement.lua',
    'client/main.lua',
    'client/ui.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/storage.lua',
    'server/framework.lua',
    'server/main.lua',
}

files {
    'stream/snipe_capsule_deck_v2.ytyp',
    'stream/snipe_capsule_canopy_v2.ytyp',
    'stream/snipe_capsule_shell_v2.ytyp',
    'stream/snipe_capsule_platform_v1.ytyp',
    'stream/snipe_capsule_tablet_v1.ytyp',
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/assets/car-silhouette.svg',
    'ui/world_dui.html',
    'ui/world_dui.css',
    'ui/world_dui.js',
}

dependencies {
    'ox_lib',
    'oxmysql',
}

data_file 'DLC_ITYP_REQUEST' 'stream/snipe_capsule_platform_v1.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/snipe_capsule_tablet_v1.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/snipe_capsule_deck_v2.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/snipe_capsule_canopy_v2.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/snipe_capsule_shell_v2.ytyp'
