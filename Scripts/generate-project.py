#!/usr/bin/env python3
"""Generate a deterministic, dependency-free Xcode project.
This writes the project structure; it is not an Apple SDK build or signing action.
Use --watch-layout watch for older tooling requiring the legacy Watch/ embed path.
"""
from pathlib import Path
import argparse,hashlib,json,plistlib,xml.etree.ElementTree as ET
R=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--watch-layout',choices=['plugins','watch'],default='plugins');args=parser.parse_args()
objects={}
def uid(key):return hashlib.sha256(('PulseLoom:'+key).encode()).hexdigest()[:24].upper()
def obj(key,isa,**attrs):
 ident=uid(key);assert ident not in objects,key;objects[ident]={'isa':isa,**attrs};return ident
main=uid('mainGroup');products=uid('productsGroup');root=uid('project')
obj('productsGroup','PBXGroup',name='Products',children=[],sourceTree='<group>')
obj('mainGroup','PBXGroup',children=[products],sourceTree='<group>')
allrefs={}
def ref(path,kind=None):
 path=str(path)
 if path in allrefs:return allrefs[path]
 ext=Path(path).suffix
 ft=kind or {'.swift':'sourcecode.swift','.plist':'text.plist.xml','.xcconfig':'text.xcconfig','.entitlements':'text.plist.entitlements','.xcprivacy':'text.xml','.xcassets':'folder.assetcatalog','.storekit':'text.json','.md':'net.daringfireball.markdown'}.get(ext,'text')
 v=obj('ref:'+path,'PBXFileReference',path=path,sourceTree='SOURCE_ROOT',lastKnownFileType=ft);allrefs[path]=v;return v
def build_ref(t,f,attributes=None):
 kw={'fileRef':f}
 if attributes:kw['settings']={'ATTRIBUTES':attributes}
 return obj('build:'+t+':'+f,'PBXBuildFile',**kw)
base=ref('Config/Base.xcconfig')
# Top-level folders are real source groups, so Find Navigator and target membership stay usable.
for folder in ['App','WatchApp','Widgets','UITests','ServiceTests','Config','Docs','Scripts','Reference']:
 group=obj('group:'+folder,'PBXGroup',name=folder,children=[],sourceTree='<group>');objects[main]['children'].append(group)
for p in sorted((R/'Config').glob('*')):
 if p.is_file():objects[uid('group:Config')]['children'].append(ref(p.relative_to(R)))
package=obj('corePackage','XCLocalSwiftPackageReference',relativePath='Packages/PulseLoomCore')
objects[main]['children'].append(ref('Packages/PulseLoomCore','folder'))
project_configs=[]
for cfg in ['Debug','Release']:
 settings={'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_WARN_DOCUMENTATION_COMMENTS':'YES','CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER':'YES','SWIFT_VERSION':'5.0','CODE_SIGN_STYLE':'Automatic','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if cfg=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if cfg=='Debug' else 'dwarf-with-dsym'}
 if cfg=='Debug':settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='$(inherited) DEBUG';settings['ENABLE_TESTABILITY']='YES'
 project_configs.append(obj('projectConfig:'+cfg,'XCBuildConfiguration',name=cfg,buildSettings=settings,baseConfigurationReference=base))
config_list=obj('projectConfigs','XCConfigurationList',buildConfigurations=project_configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
targets={};target_products={}
specs=[('PulseLoom','App','com.apple.product-type.application','iphoneos','17.0','$(APP_BUNDLE_ID)','app'),('PulseLoomWatch','WatchApp','com.apple.product-type.application','watchos','10.0','$(APP_BUNDLE_ID).watchkitapp','app'),('PulseLoomWidgets','Widgets','com.apple.product-type.app-extension','iphoneos','17.0','$(APP_BUNDLE_ID).widgets','appex'),('PulseLoomServiceTests','ServiceTests','com.apple.product-type.bundle.unit-test','iphoneos','17.0','$(APP_BUNDLE_ID).servicetests','xctest'),('PulseLoomUITests','UITests','com.apple.product-type.bundle.ui-testing','iphoneos','17.0','$(APP_BUNDLE_ID).uitests','xctest')]
for name,folder,ptype,sdk,minimum,bundle,ext in specs:
 tid=uid('target:'+name);targets[name]=tid
 product=obj('product:'+name,'PBXFileReference',explicitFileType='wrapper.application' if ext=='app' else 'wrapper.app-extension' if ext=='appex' else 'wrapper.cfbundle',includeInIndex=0,path=name+'.'+ext,sourceTree='BUILT_PRODUCTS_DIR')
 target_products[name]=product;objects[products]['children'].append(product)
 source_files=[]
 for p in sorted((R/folder).rglob('*.swift')):
  f=ref(p.relative_to(R));objects[uid('group:'+folder)]['children'].append(f);source_files.append(build_ref(name,f))
 sources=obj('sources:'+name,'PBXSourcesBuildPhase',buildActionMask=2147483647,files=source_files,runOnlyForDeploymentPostprocessing=0)
 resources=[]
 resource_root=R/folder/'Resources'
 if resource_root.exists():
  for p in sorted(resource_root.iterdir()):
   if p.name.endswith('.lproj'):continue
   f=ref(p.relative_to(R));objects[uid('group:'+folder)]['children'].append(f);resources.append(build_ref(name,f))
  for filename in ['Localizable.strings','InfoPlist.strings','Recovery.strings']:
   local=[]
   for lang in ['en','zh-Hans','ja']:
    path=resource_root/(lang+'.lproj')/filename
    if path.exists():local.append(obj('locale:'+name+':'+lang+':'+filename,'PBXFileReference',name=lang,path=str(path.relative_to(R)),sourceTree='SOURCE_ROOT',lastKnownFileType='text.plist.strings'))
   if local:
    vg=obj('variant:'+name+':'+filename,'PBXVariantGroup',name=filename,children=local,sourceTree='<group>');objects[uid('group:'+folder)]['children'].append(vg);resources.append(build_ref(name,vg))
 resource_phase=obj('resources:'+name,'PBXResourcesBuildPhase',buildActionMask=2147483647,files=resources,runOnlyForDeploymentPostprocessing=0)
 framework_files=[];package_products=[]
 if name in ['PulseLoom','PulseLoomServiceTests']:
  pp=obj('packageProduct:'+name,'XCSwiftPackageProductDependency',package=package,productName='PulseLoomCore');package_products.append(pp)
  framework_files.append(obj('packageBuild:'+name,'PBXBuildFile',productRef=pp))
 framework_phase=obj('frameworks:'+name,'PBXFrameworksBuildPhase',buildActionMask=2147483647,files=framework_files,runOnlyForDeploymentPostprocessing=0)
 settings={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':bundle,'SDKROOT':sdk,'SUPPORTED_PLATFORMS':'watchos watchsimulator' if sdk=='watchos' else 'iphoneos iphonesimulator','SWIFT_VERSION':'5.0','SWIFT_STRICT_CONCURRENCY':'targeted','TARGETED_DEVICE_FAMILY':'4' if sdk=='watchos' else '1','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks'],'SKIP_INSTALL':'NO' if name=='PulseLoom' else 'YES','GENERATE_INFOPLIST_FILE':'NO','SUPPORTS_MACCATALYST':'NO','SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO','SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD':'NO'}
 settings['WATCHOS_DEPLOYMENT_TARGET' if sdk=='watchos' else 'IPHONEOS_DEPLOYMENT_TARGET']=minimum
 if name=='PulseLoom':
  settings.update(INFOPLIST_FILE='Config/App-Info.plist',CODE_SIGN_ENTITLEMENTS='Config/App.entitlements',ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon',ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES=['MistIcon','NightIcon'],ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS='YES')
 elif name=='PulseLoomWatch':settings.update(INFOPLIST_FILE='Config/Watch-Info.plist',CODE_SIGN_ENTITLEMENTS='Config/Watch.entitlements',ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon')
 elif name=='PulseLoomWidgets':settings.update(INFOPLIST_FILE='Config/Widgets-Info.plist',CODE_SIGN_ENTITLEMENTS='Config/Widgets.entitlements',APPLICATION_EXTENSION_API_ONLY='YES',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks','@executable_path/../../Frameworks'])
 elif name=='PulseLoomServiceTests':settings.update(GENERATE_INFOPLIST_FILE='YES',TEST_HOST='$(BUILT_PRODUCTS_DIR)/PulseLoom.app/PulseLoom',BUNDLE_LOADER='$(TEST_HOST)')
 else:settings.update(GENERATE_INFOPLIST_FILE='YES',TEST_TARGET_NAME='PulseLoom')
 configs=[]
 for cfg in ['Debug','Release']:
  s=settings.copy()
  if cfg=='Debug':s.update(SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DEBUG',ENABLE_TESTABILITY='YES')
  configs.append(obj('config:'+name+':'+cfg,'XCBuildConfiguration',name=cfg,buildSettings=s,baseConfigurationReference=base))
 cl=obj('configs:'+name,'XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
 obj('target:'+name,'PBXNativeTarget',name=name,productName=name,productType=ptype,productReference=product,buildConfigurationList=cl,buildPhases=[sources,framework_phase,resource_phase],buildRules=[],dependencies=[],packageProductDependencies=package_products)

def dependency(parent,child):
 proxy=obj('proxy:'+parent+':'+child,'PBXContainerItemProxy',containerPortal=root,proxyType=1,remoteGlobalIDString=targets[child],remoteInfo=child)
 dep=obj('dependency:'+parent+':'+child,'PBXTargetDependency',target=targets[child],targetProxy=proxy)
 objects[targets[parent]]['dependencies'].append(dep)
for child in ['PulseLoomWatch','PulseLoomWidgets']:dependency('PulseLoom',child)
dependency('PulseLoomUITests','PulseLoom')
dependency('PulseLoomServiceTests','PulseLoom')
for child,phase_name,destination,path in [('PulseLoomWidgets','Embed Widgets',13,''),('PulseLoomWatch','Embed Watch Content',13 if args.watch_layout=='plugins' else 16,'' if args.watch_layout=='plugins' else '$(CONTENTS_FOLDER_PATH)/Watch')]:
 bf=build_ref('embed:'+child,target_products[child],['RemoveHeadersOnCopy'])
 phase=obj('embedPhase:'+child,'PBXCopyFilesBuildPhase',name=phase_name,buildActionMask=2147483647,dstPath=path,dstSubfolderSpec=destination,files=[bf],runOnlyForDeploymentPostprocessing=0)
 objects[targets['PulseLoom']]['buildPhases'].append(phase)
attrs={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'1600','TargetAttributes':{v:{'CreatedOnToolsVersion':'16.0','ProvisioningStyle':'Automatic'} for v in targets.values()}}
attrs['TargetAttributes'][targets['PulseLoom']]['SystemCapabilities']={'com.apple.ApplicationGroups.iOS':{'enabled':1},'com.apple.iCloud':{'enabled':1},'com.apple.InAppPurchase':{'enabled':1}}
attrs['TargetAttributes'][targets['PulseLoomWidgets']]['SystemCapabilities']={'com.apple.ApplicationGroups.iOS':{'enabled':1}}
obj('project','PBXProject',attributes=attrs,buildConfigurationList=config_list,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base','zh-Hans','ja'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',targets=list(targets.values()),packageReferences=[package])

def osvalue(v,level=0):
 t='\t'*level
 if isinstance(v,dict):return '{\n'+''.join(t+'\t'+json.dumps(str(k))+' = '+osvalue(val,level+1)+';\n' for k,val in v.items())+t+'}'
 if isinstance(v,list):return '(\n'+''.join(t+'\t'+osvalue(x,level+1)+',\n' for x in v)+t+')'
 if isinstance(v,int):return str(v)
 return json.dumps(str(v),ensure_ascii=False)
p=R/'PulseLoom.xcodeproj';p.mkdir(exist_ok=True)
project={'archiveVersion':1,'classes':{},'objectVersion':60,'objects':objects,'rootObject':root}
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n'+osvalue(project)+'\n')
w=p/'project.xcworkspace';w.mkdir(exist_ok=True);(w/'contents.xcworkspacedata').write_text('<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="self:"/></Workspace>\n')

def buildable(parent,name):
 return ET.SubElement(parent,'BuildableReference',{'BuildableIdentifier':'primary','BlueprintIdentifier':targets[name],'BuildableName':name+'.'+('xctest' if name in ['PulseLoomUITests','PulseLoomServiceTests'] else 'appex' if name=='PulseLoomWidgets' else 'app'),'BlueprintName':name,'ReferencedContainer':'container:PulseLoom.xcodeproj'})
def scheme(name,watch=False,fixture=False,services=False):
 s=ET.Element('Scheme',{'LastUpgradeVersion':'1600','version':'1.7'});primary='PulseLoomWatch' if watch else 'PulseLoom'
 ba=ET.SubElement(s,'BuildAction',{'parallelizeBuildables':'YES','buildImplicitDependencies':'YES'});entries=ET.SubElement(ba,'BuildActionEntries')
 e=ET.SubElement(entries,'BuildActionEntry',{k:'YES' for k in ['buildForTesting','buildForRunning','buildForProfiling','buildForArchiving','buildForAnalyzing']});buildable(e,primary)
 if not watch:
  ta=ET.SubElement(s,'TestAction',{'buildConfiguration':'Debug','selectedDebuggerIdentifier':'Xcode.DebuggerFoundation.Debugger.LLDB','selectedLauncherIdentifier':'Xcode.IDEFoundation.Launcher.LLDB','shouldUseLaunchSchemeArgsEnv':'YES'})
  expansion=ET.SubElement(ta,'MacroExpansion');buildable(expansion,primary)
  ts=ET.SubElement(ta,'Testables');tr=ET.SubElement(ts,'TestableReference',{'skipped':'NO'});buildable(tr,'PulseLoomServiceTests' if services else 'PulseLoomUITests')
 launch=ET.SubElement(s,'LaunchAction',{'buildConfiguration':'Debug','selectedDebuggerIdentifier':'Xcode.DebuggerFoundation.Debugger.LLDB','selectedLauncherIdentifier':'Xcode.IDEFoundation.Launcher.LLDB','launchStyle':'0','useCustomWorkingDirectory':'NO','ignoresPersistentStateOnLaunch':'NO','debugDocumentVersioning':'YES','allowLocationSimulation':'NO'})
 run=ET.SubElement(launch,'BuildableProductRunnable',{'runnableDebuggingMode':'0'});buildable(run,primary)
 if fixture:ET.SubElement(launch,'StoreKitConfigurationFileReference',{'identifier':'../../Config/PulseLoom.storekit'})
 profile=ET.SubElement(s,'ProfileAction',{'buildConfiguration':'Release','shouldUseLaunchSchemeArgsEnv':'YES','savedToolIdentifier':'','useCustomWorkingDirectory':'NO','debugDocumentVersioning':'YES'});buildable(ET.SubElement(profile,'BuildableProductRunnable',{'runnableDebuggingMode':'0'}),primary)
 ET.SubElement(s,'AnalyzeAction',{'buildConfiguration':'Debug'});ET.SubElement(s,'ArchiveAction',{'buildConfiguration':'Release','revealArchiveInOrganizer':'YES'})
 out=p/'xcshareddata/xcschemes';out.mkdir(parents=True,exist_ok=True);ET.indent(s);ET.ElementTree(s).write(out/(name+'.xcscheme'),encoding='utf-8',xml_declaration=True)
scheme('PulseLoom');scheme('PulseLoom-StoreKit',fixture=True);scheme('PulseLoomWatch',watch=True);scheme('PulseLoom-ServiceTests',services=True)
# Structural record is validation input; it does not assert SDK compilation.
(R/'Config/project-manifest.json').write_text(json.dumps({'generator':1,'watchEmbedLayout':args.watch_layout,'targets':targets,'sourceFiles':[str(p.relative_to(R)) for folder in ['App','WatchApp','Widgets','UITests','ServiceTests'] for p in sorted((R/folder).rglob('*.swift'))],'objectCount':len(objects)},indent=2)+'\n')
print(f'Generated {p.name}: {len(targets)} targets, {len(objects)} objects; Watch embed={args.watch_layout}.')
