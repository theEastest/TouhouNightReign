---=====================================
---THlib
---Touhou style library
---=====================================

----------------------------------------
---加载脚本

Include 'THlib/ex.lua' --ESC的ex库
Include 'THlib/WalkImageSystem.lua'
Include 'THlib/DNHWalkImageSystem.lua'
Include 'THlib/DNHRenderObject.lua'
Include 'THlib/resourcesRedirect.lua'
Include 'THlib/misc/misc.lua'
Include 'THlib/se/se.lua'
Include 'THlib/item/item.lua'
Include 'THlib/player/player.lua'
Include 'THlib/enemy/enemy.lua'
Include 'THlib/bullet/bullet.lua'
-- The project-owned bullet.lua contains the class implementations, while the
-- original THlib resource script owns the atlas registrations. Keep both
-- halves in the same initialization order so every legacy style (including
-- kite12 and the animation-based styles) has its real image resource.
Include 'THlib/bullet/legacy_bullet_load_resources.txt'
Include 'THlib/bullet/bullet_others.lua'
Include 'THlib/bullet/legacy_bullet_styles.lua'
Include 'THlib/laser/laser.lua'
Include 'THlib/background/background.lua'
Include 'THlib/ext/ext.lua'
Include 'THlib/UI/menu.lua'
Include 'THlib/editor.lua'
Include 'THlib/UI/UI.lua'
Include 'sp/sp.lua'--OLC神的sp加强库
