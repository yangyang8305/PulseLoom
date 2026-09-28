#!/usr/bin/env python3
"""Generate owned icon artwork, launch assets, plists, entitlements and privacy manifests.
No downloaded fonts or artwork. Does not contact Apple or create account capabilities.
"""
from pathlib import Path
import json,math,plistlib
from PIL import Image,ImageDraw,ImageFilter
R=Path(__file__).resolve().parents[1]
def plist(path,obj):
 p=R/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(plistlib.dumps(obj,sort_keys=True))
def js(path,obj):
 p=R/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(obj,indent=2)+'\n')
info={'CFBundleDevelopmentRegion':'$(DEVELOPMENT_LANGUAGE)','CFBundleDisplayName':'Pulse Loom','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'$(PRODUCT_BUNDLE_PACKAGE_TYPE)','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)'}
app=dict(info,LSRequiresIPhoneOS=True,UILaunchScreen={'UIColorName':'LaunchBackground','UIImageName':'LaunchMark','UIImageRespectsSafeAreaInsets':True},UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait'],UIApplicationSupportsIndirectInputEvents=True,UIApplicationSceneManifest={'UIApplicationSupportsMultipleScenes':False},NSAppleMusicUsageDescription='Choose and play Apple Music tracks with your permission.',MusicHapticsSupported=True,ITSAppUsesNonExemptEncryption=False,CFBundleURLTypes=[{'CFBundleURLName':'com.yoyo.PulseLoom','CFBundleURLSchemes':['pulseloom']}],AppGroupID='$(APP_GROUP_ID)',CloudContainerID='$(CLOUD_CONTAINER_ID)',ProProductID='$(PRO_PRODUCT_ID)',RelayBaseURL='$(RELAY_BASE_URL)',SupportURL='$(SUPPORT_URL)')
plist('Config/App-Info.plist',app)
plist('Config/Watch-Info.plist',dict(info,WKApplication=True,WKCompanionAppBundleIdentifier='$(APP_BUNDLE_ID)',WKRunsIndependentlyOfCompanionApp=False,ITSAppUsesNonExemptEncryption=False))
plist('Config/Widgets-Info.plist',dict(info,AppGroupID='$(APP_GROUP_ID)',NSExtension={'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}))
plist('Config/App.entitlements',{'com.apple.security.application-groups':['$(APP_GROUP_ID)'],'com.apple.developer.icloud-container-identifiers':['$(CLOUD_CONTAINER_ID)'],'com.apple.developer.icloud-services':['CloudKit'],'com.apple.developer.default-data-protection':'NSFileProtectionCompleteUntilFirstUserAuthentication'})
plist('Config/Widgets.entitlements',{'com.apple.security.application-groups':['$(APP_GROUP_ID)']})
# MusicKit is an App ID service, NOT a fabricated com.apple.developer.musickit entitlement.
plist('Config/Watch.entitlements',{})
def privacy(apis,collections=()):
 return {'NSPrivacyTracking':False,'NSPrivacyTrackingDomains':[],'NSPrivacyCollectedDataTypes':list(collections),'NSPrivacyAccessedAPITypes':[{'NSPrivacyAccessedAPIType':k,'NSPrivacyAccessedAPITypeReasons':v} for k,v in apis]}
# Conservative declarations: optional cloud/support and transient relay metadata. Final store labels require review of deployed infrastructure.
collections=[{'NSPrivacyCollectedDataType':t,'NSPrivacyCollectedDataTypeLinked':False,'NSPrivacyCollectedDataTypeTracking':False,'NSPrivacyCollectedDataTypePurposes':['NSPrivacyCollectedDataTypePurposeAppFunctionality']} for t in ['NSPrivacyCollectedDataTypeOtherUserContent','NSPrivacyCollectedDataTypeOtherDataTypes']]
plist('App/Resources/PrivacyInfo.xcprivacy',privacy([('NSPrivacyAccessedAPICategoryUserDefaults',['1C8F.1']),('NSPrivacyAccessedAPICategorySystemBootTime',['35F9.1']),('NSPrivacyAccessedAPICategoryFileTimestamp',['C617.1','3B52.1'])],collections))
plist('Widgets/Resources/PrivacyInfo.xcprivacy',privacy([('NSPrivacyAccessedAPICategoryUserDefaults',['1C8F.1'])]))
plist('WatchApp/Resources/PrivacyInfo.xcprivacy',privacy([]))

def icon(kind):
 palettes={'AppIcon':('#fcf7f3','#b9879b','#f3dde4'),'MistIcon':('#f5f2fa','#9784bb','#e1d9ef'),'NightIcon':('#18161f','#b29ac9','#3b2c47')}
 bg,ink,petal=palettes[kind];im=Image.new('RGB',(1024,1024),bg)
 layer=Image.new('RGBA',im.size);d=ImageDraw.Draw(layer)
 for i in range(9):
  a=(i-4)*.22;pts=[]
  for j in range(100):
   t=j/99;shape=math.sin(math.pi*t)*118;x=shape;y=-420*t
   pts.append((512+x*math.cos(a)-y*math.sin(a),765+x*math.sin(a)+y*math.cos(a)))
  for j in range(99,-1,-1):
   t=j/99;shape=-math.sin(math.pi*t)*118;x=shape;y=-420*t
   pts.append((512+x*math.cos(a)-y*math.sin(a),765+x*math.sin(a)+y*math.cos(a)))
  d.polygon(pts,fill=petal+'8a',outline=ink+'65')
 im=Image.alpha_composite(im.convert('RGBA'),layer)
 d=ImageDraw.Draw(im)
 pts=[(x,770+13*math.sin((x-260)/70)) for x in range(268,758)]
 d.line(pts,fill=ink,width=5)
 return im.convert('RGB')
assets=R/'App/Resources/Assets.xcassets';js(assets.relative_to(R)/'Contents.json',{'info':{'author':'xcode','version':1}})
for name in ['AppIcon','MistIcon','NightIcon']:
 p=assets/(name+'.appiconset');p.mkdir(parents=True,exist_ok=True);icon(name).save(p/'icon-1024.png')
 js(p.relative_to(R)/'Contents.json',{'images':[{'filename':'icon-1024.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}})
launch=assets/'LaunchMark.imageset';launch.mkdir(parents=True,exist_ok=True)
icon('AppIcon').resize((420,420),Image.Resampling.LANCZOS).save(launch/'launch.png')
icon('NightIcon').resize((420,420),Image.Resampling.LANCZOS).save(launch/'launch-dark.png')
js(launch.relative_to(R)/'Contents.json',{'images':[{'filename':'launch.png','idiom':'universal','scale':'1x'},{'filename':'launch-dark.png','idiom':'universal','scale':'1x','appearances':[{'appearance':'luminosity','value':'dark'}]}],'info':{'author':'xcode','version':1}})
js((assets/'LaunchBackground.colorset/Contents.json').relative_to(R),{'colors':[{'idiom':'universal','color':{'color-space':'srgb','components':{'red':'0.988','green':'0.969','blue':'0.953','alpha':'1.000'}}},{'idiom':'universal','appearances':[{'appearance':'luminosity','value':'dark'}],'color':{'color-space':'srgb','components':{'red':'0.082','green':'0.082','blue':'0.102','alpha':'1.000'}}}],'info':{'author':'xcode','version':1}})
wa=R/'WatchApp/Resources/Assets.xcassets';js(wa.relative_to(R)/'Contents.json',{'info':{'author':'xcode','version':1}})
wicon=wa/'AppIcon.appiconset';wicon.mkdir(parents=True,exist_ok=True);icon('AppIcon').save(wicon/'icon-1024.png')
js(wicon.relative_to(R)/'Contents.json',{'images':[{'filename':'icon-1024.png','idiom':'universal','platform':'watchos','size':'1024x1024'}],'info':{'author':'xcode','version':1}})
print('Plists, entitlement files, 3 privacy manifests and owned icon assets generated.')
