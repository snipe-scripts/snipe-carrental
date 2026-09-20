CapsuleDuiConfig = {
    page = 'ui/world_dui.html',
    width = 640,
    height = 960,
    maxUpdateDistance = 85.0,
    maxInteractionDistance = 6.5,
    retryDelay = 5000,
    -- Both custom terminals use this shared 2:3 UV-mapped screen texture.
    textureDictionary = 'snipe_capsule_txd_v1',
    textureName = 'snipe_capsule_screen_d',
    -- Local model-space screen planes. These match the UV-mapped geometry in
    -- the custom YDRs and are used to project the NUI cursor into DUI pixels.
    screens = {
        tablet = { x = 0.0, y = -0.081, z = 1.390, width = 0.56, height = 0.84 },
    },
    camera = {
        fov = 42.0,
        padding = 0.30,
        nearClip = 0.05,
        transitionIn = 350,
        transitionOut = 250,
    },
}
