---
title: "ARK: Survival Ascended Server構築記 その1 Compute EngineでServerを動かす"
emoji: "🦖"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["gcp"]
published: false
---

筆者が友人数人とマルチプレイで遊んでいる [ARK: Survival Ascended](https://store.steampowered.com/app/2399830/ARK_Survival_Ascended/?l=japanese) (以下ASA) のサーバの構築運用記です。
ARKのサーバとしては少々特殊で、誰かが遊んでいる時しか起動していないサーバになります。
サーバ自身はCompute Engineで動かしていますが、起動と停止はCloud Runで行っていたりと、Google Cloudのいくつかのプロダクトを使っています。
同じことをしたい方はあまりいないとは思いますが、どのような構成になっているかを記しておきます。
使っている機能についてはある程度、公式ドキュメントへのLinkを貼っていますが、細かくは説明してないので、Google Cloudをある程度は知っている人向けの内容です。

長くなるので、いくつかのレイヤーに分けて記事を書いていこうと思います。
この記事は1つ目です。

* その1 Compute EngineでServerを動かす
* その2 サーバの起動と自動停止を行うDiscord BotとAgent
* その3 生物のステータスをBigQueryで整理する

## Compute Engine Insntaceの作成

まずはCompute EngineのInstanceで利用するService Accountを作ります。
Defaultで用意されているCompute Engine Default Service Account使っても良いのですが、自分はあのService Accountを使うのはあまり好きではないので、個別に作ります。
興味がある方は [Service Accountの運用について](https://github.com/gcpug/nouhau/tree/master/general/note/destroy-service-account-key) を読むとService Accountへの理解が深まります。

RoleとしてCloud StorageへのアクセスやOperation SuiteへのWriteを付けておきます。
Cloud StorageへのアクセスはBucketごとに真面目に設定した方が本当は良いですが、横着してProject Levelで付けてます。
リソースはWeb UIやTerraformで作っても良いですが、この記事では [Cloud SDK](https://cloud.google.com/sdk) のコマンドで書いています。
Cloud SDKがマシンに入っている場合はLocalで実行すれば良いですが、入ってない場合は [Cloud Shell](https://cloud.google.com/shell) で実行するのが楽です。

```shell:PROJECT_IDの設定
export GOOGLE_CLOUD_PROJECT={YOUR_PROJECT_ID}
```

``` shell:Service Accountの作成とRoleの付与
gcloud iam service-accounts create ark-server --description="ARK Server Worker" --display-name="ark-server"
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT --member=serviceAccount:ark-server@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role=roles/storage.admin
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT --member=serviceAccount:ark-server@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role=roles/logging.logWriter
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT --member=serviceAccount:ark-server@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role=roles/monitoring.metricWriter
```

Service Accountが作れたら、Instanceを作ります。
ASAはメモリを16GB弱使うのでマシンタイプは `e2-highmem-2` を使い、Diskは50GBのBalanced Persistent Diskを使っています。
CPU利用率もメモリ利用率80%ほどになります。
CPUのコアを増やせば、サーバの動きが軽くなったりするかと思って試してみたのですが、コアを増やしても使われていないようだったので、 `e2-highmem-2` にしています。

``` shell:Instanceの作成コマンド
gcloud compute instances create asa-island \
    --project=$GOOGLE_CLOUD_PROJECT \
    --zone=asia-northeast1-b \
    --machine-type=e2-highmem-2 \
    --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --service-account=ark-server@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --create-disk=auto-delete=yes,boot=yes,device-name=asa-island,image=projects/debian-cloud/global/images/debian-12-bookworm-v20231115,mode=rw,size=50,type=projects/$GOOGLE_CLOUD_PROJECT/zones/asia-northeast1-b/diskTypes/pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels=goog-ec-src=vm_add-gcloud \
    --reservation-affinity=any
```

## ARK Server Install

ARKのServer ApplicationのInstallは　https://github.com/cdp1337/ARKSurvivalAscended-Linux を参考にしています。
実行すればInstallが完了するshellを用意してくれているので、これを使ってInstallします。
ただ、Install後に修正を加えています。
`GameUserSettings.ini` のシンボリックリンクが貼られているのですが、自分はサーバ上で編集するのではなく、GitHub上で管理してアップロードするので、シンボリックリンクは不要です。

``` shell:シンボリックリンクの削除 (Compute Engine上で実行)
sudo unlink /home/steam/island-GameUserSettings.ini
```

### GameSettings Fileの準備

ARKでは `GameUserSettings.ini` と `Game.ini` の2つの設定ファイルがあるので、どちらも用意します。
主にゲームバランスに関する設定ですが、Port番号やサーバリストに表示される名前など、いくつかサーバ管理のための値があります。

設定ファイルが作成できたら、Cloud Storageにアップロードしておきます。
筆者はGitHubで管理しているので、 [Cloud Build Trigger](https://cloud.google.com/build/docs/triggers) を利用して、BranchがPushされたら、Cloud Storageにアップロードするようにしています。
以下はLocalで作成した設定ファイルをCloud Storageにアップロードする例です。

``` shell:設定ファイル用Bucketの作成
gcloud storage buckets create gs://metal-ark-sample-config -l asia-northeast1
```

``` shell:設定ファイルをCloud Storageにアップロード
gcloud storage cp GameUserSettings.ini gs://metal-ark-sample-config/island/GameUserSettings.ini
gcloud storage cp Game.ini gs://metal-ark-sample-config/island/Game.ini
```

以下は筆者の設定ファイルのサンプルです。
参考程度にどうぞ。
もし真似する場合は以下の2つは必ず変更が必要です。

* `SessionName=asa-sample-island` : Server検索時に表示される名前
* `ServerAdminPassword=xxxxxxxx` : 管理者コマンド用パスワード

:::details GameUserSettings.ini

``` ini:GameUserSettings.ini
[ServerSettings]
ServerAdminPassword=xxxxxxxx
ServerPVE=True
ShowMapPlayerLocation=True
AllowThirdPersonPlayer=True
ServerCrosshair=True
RCONPort=27020
RCONEnabled=True
TheMaxStructuresInRange=10500
StartTimeHour=-1
OxygenSwimSpeedStatMultiplier=1
StructurePreventResourceRadiusMultiplier=1
TribeNameChangeCooldown=15
PlatformSaddleBuildAreaBoundsMultiplier=1
AlwaysAllowStructurePickup=True
StructurePickupTimeAfterPlacement=30
StructurePickupHoldDuration=0.5
AllowHideDamageSourceFromLogs=True
RaidDinoCharacterFoodDrainMultiplier=1
PvEDinoDecayPeriodMultiplier=1
KickIdlePlayersPeriod=3600
PerPlatformMaxStructuresMultiplier=1
AutoSavePeriodMinutes=15
MaxTamedDinos=5000
ItemStackSizeMultiplier=1
RCONServerGameLogBuffer=600
ImplantSuicideCD=28800
AllowHitMarkers=True
TamingSpeedMultiplier=4.000000
HarvestAmountMultiplier=3.000000
XPMultiplier=3.000000
DifficultyOffset=1.0
OverrideOfficialDifficulty=5.0
ShowFloatingDamageText=True
AllowAnyoneBabyImprintCuddle=True
EnablePVPGamma=False
DisablePvEGamma=False
AllowFlyerCarryPvE=True

[ScalabilityGroups]
sg.ResolutionQuality=75
sg.ViewDistanceQuality=1
sg.AntiAliasingQuality=1
sg.ShadowQuality=2
sg.GlobalIlluminationQuality=3
sg.ReflectionQuality=3
sg.PostProcessQuality=1
sg.TextureQuality=2
sg.EffectsQuality=1
sg.FoliageQuality=2
sg.ShadingQuality=3

[/Script/ShooterGame.ShooterGameUserSettings]
AdvancedGraphicsQuality=1
MasterAudioVolume=1.000000
MusicAudioVolume=0.800000
SFXAudioVolume=1.000000
VoiceAudioVolume=1.000000
SoundUIAudioVolume=1.000000
CharacterAudioVolume=1.000000
StructureTooltipMaxSpeedMultiply=0.000000
UIScaling=1.000000
UIQuickbarScaling=0.750000
CameraShakeScale=0.650000
bFirstPersonRiding=False
bThirdPersonPlayer=True
bShowStatusNotificationMessages=True
TrueSkyQuality=0.270000
FOVMultiplier=1.000000
GroundClutterDensity=1.000000
bFilmGrain=False
bMotionBlur=True
bUseGamepadSpeaker=True
bUseDFAO=False
bUseSSAO=True
bShowChatBox=True
bCameraViewBob=True
bInvertLookY=False
bFloatingNames=True
bChatBubbles=True
bHideServerInfo=False
bJoinNotifications=False
bDisableNameYourTamePopup=False
MinimalFloatingNameSetting=False
bCraftablesShowAllItems=False
bLocalInventoryItemsShowAllItems=False
bLocalInventoryCraftingShowAllItems=True
bRemoteInventoryItemsShowAllItems=False
bRemoteInventoryCraftingShowAllItems=False
bRemoteInventoryShowEngrams=True
bEnableLowLightEnhancement=True
bEnableFluidInteraction=True
bDisableHLOD=False
LookLeftRightSensitivity=1.000000
LookUpDownSensitivity=1.000000
TPVCameraHorizontalOffsetFactor=0.000000
GraphicsQuality=1
ActiveLingeringWorldTiles=10
ClientNetQuality=3
TheGammaCorrection=0.500000
LastServerSearchType=0
LastServerSort=2
LastPVESearchType=-1
LastDLCTypeSearchType=-1
LastServerSortAsc=True
LastAutoFavorite=True
LastServerSearchHideFull=False
LastServerSearchProtected=False
LastPlatformSpecificServerSearch=False
HideItemTextOverlay=True
bForceShowItemNames=False
bDistanceFieldShadowing=True
bDisableShadows=False
LODScalar=1.000000
bToggleToTalk=False
HighQualityMaterials=True
HighQualitySurfaces=True
bTemperatureF=False
bDisableTorporEffect=False
bChatShowSteamName=False
bChatShowTribeName=True
bReverseTribeLogOrder=False
EmoteKeyBind1=0
EmoteKeyBind2=0
bNoBloodEffects=False
bLowQualityVFX=False
bSpectatorManualFloatingNames=False
bSuppressAdminIcon=False
bUseSimpleDistanceMovement=False
bHasSavedGame=False
bDisableMeleeCameraSwingAnims=False
bPreventInventoryOpeningSounds=False
bPreventBiomeWalls=False
bPreventHitMarkers=False
bPreventCrosshair=False
bPreventColorizedItemNames=False
bHighQualityLODs=False
bExtraLevelStreamingDistance=False
bEnableColorGrading=False
VSyncMode=1
DOFSettingInterpTime=0.000000
LastJoinedSessionPerCategory=" "
LastJoinedSessionPerCategory=" "
LastJoinedSessionPerCategory=" "
LastJoinedSessionPerCategory=" "
LastJoinedSessionPerCategory=" "
LastJoinedSessionPerCategory=" "
LastJoinedSessionPerCategory=" "
LastJoinedSessionPerCategory=" "
LastJoinedSessionPerCategory=" "
LastSessionCategoryJoined=-1
bDisableMenuTransitions=False
bEnableInventoryItemTooltips=True
bRemoteInventoryShowCraftables=False
bNoTooltipDelay=False
LocalItemSortType=0
LocalCraftingSortType=0
RemoteItemSortType=0
RemoteCraftingSortType=0
VersionMetaTag=1
ShowExplorerNoteSubtitles=False
DisableMenuMusic=False
DisableDefaultCharacterItems=False
DisableLoadScreenMusic=False
bRequestDefaultCharacterItemsOnce=False
bHasSeenGen2Intro=False
CinematicForNoteShouldReset=()
bHasSetupDifficultySP=False
bHasSetupVisualSettings=False
agreedToTerms=()
bHasRunAutoSettings=False
bHideFloatingPlayerNames=False
bHideGamepadItemSelectionModifier=False
bToggleExtendedHUDInfo=False
PlayActionWheelClickSound=True
PlayHUDRolloverSound=True
CompanionReactionVerbosity=3
EnableEnvironmentalReactions=True
EnableRespawnReactions=True
EnableDeathReactions=True
EnableSayHelloReactions=True
EnableEmoteReactions=True
EnableMovementSounds=True
DisableSubtitles=False
bEnableASACamera=True
ConsoleAccess=False
CompanionSubtitleVerbosityLevel=3
CompanionIsHiddenState=False
MaxAscensionLevel=0
bHostSessionHasBeenOpened=False
bForceTPVCameraOffset=False
bDisableTPVCameraInterpolation=False
bEnableHDROutput=False
HDRDisplayMinLuminance=-4.000000
HDRDisplayMidLuminance=20.000000
HDRDisplayMaxLuminance=1400.000000
FoliageInteractionDistance=1.000000
FoliageInteractionDistanceLimit=1.000000
FoliageInteractionQuantityLimit=1.000000
bFPVClimbingGear=False
bFPVGlidingGear=False
bHasInitializedScreenPercentage=False
CameraZoomPerDinoNameTag=()
CameraHeightPerDinoNameTag=()
PhotomodePresets_Camera=()
PhotomodePresets_Movement=()
PhotomodePresets_Splines=()
PhotomodePresets_PPs=()
PhotomodePresets_Targeting=()
PhotomodeLastUsedSettings=()
MaxLastDeathMark=5
bSaveLastDeathMark=True
bShowPingsOnMap=True
bShowDinosOnMap=True
bShowWaypointsOnMap=True
bShowPlayersOnMap=True
bShowBedsOnMap=True
AimAssistStrengthMultiplier=1.000000
bForceShowRadialWheelTexts=False
bHideStructurePlacementCrosshair=False
SavedMainMapZoom=1.000000
SavedOverlayMapZoom=1.000000
bMinimalUI=False
FloatingTooltipStructureMode=DEFAULT
FloatingTooltipDinoMode=DEFAULT
FloatingTooltipDroppedItemsMode=DEFAULT
FloatingTooltipPlayerMode=DEFAULT
TopNotificationMode=DEFAULT
ItemNotificationMode=MINIMAL
bMinimapOverlayUseLowOpacity=False
FilterTypeInventoryLocal=9
FilterTypeInventoryRemote=9
bUseGamepadAimAssist=RangeWeaponAlwaysOn
Gamma1=2.200000
Gamma2=3.000000
bDisableBloom=False
bDisableLightShafts=False
bUseLowQualityLevelStreaming=True
bUseDistanceFieldAmbientOcclusion=False
bPreventItemCraftingSounds=False
bHighQualityAnisotropicFiltering=False
AmbientSoundVolume=1.000000
bUseOldThirdPersonCameraTrace=False
bUseOldThirdPersonCameraOffset=False
bShowedGenesisDLCBackground=False
bShowedGenesis2DLCBackground=False
bHasStartedTheGameOnce=False
bViewedAnimatedSeriesTrailer=False
bViewedARK2Trailer=False
bShowRTSKeyBinds=True
bHasCompletedGen2=False
bEnableFootstepDecals=True
bEnableFootstepParticles=True
bShowInfoButtons=True
bDisablePaintings=False
StopExplorerNoteAudioOnClose=False
bVibration=True
bUIVibration=False
radialSelectionSpeed=0.650000
bDisableVirtualCursor=False
PreventDetailGraphics=False
GroundClutterRadius=0
HFSQuality=0
bMenuGyro=False
gyroSensitivity=0.500000
virtualCursorSensitivity=0.500000
BubbleParticlesMultiplier=1.000000
CrosshairScale=1.000000
CrosshairOpacity=1.000000
CrosshairColor=(R=1.000000,G=1.000000,B=1.000000,A=1.000000)
CrosshairColorPickerValue=(X=0.000000,Y=0.000000)
CrosshairColorOverEnemy=(R=0.000000,G=0.376471,B=1.000000,A=1.000000)
CrosshairColorPickerValueOverEnemy=(X=0.010000,Y=0.500000)
CrosshairColorOverAlly=(R=0.000000,G=1.000000,B=0.000000,A=1.000000)
CrosshairColorPickerValueOverAlly=(X=0.260000,Y=0.440000)
CrosshairColorHitmark=(R=1.000000,G=0.000000,B=0.000000,A=1.000000)
CrosshairColorPickerValueHitmark=(X=0.010000,Y=0.640000)
CurrentCameraModeIndex=2
CurrentDinoCameraModeIndex=1
bShowAmbientInsectsVFX=True
TextChatFilterType=0
VoiceChatFilterType=0
bAutomaticallyCreateWaypointOnTamingCreatures=True
bAutomaticallyCreatePOIOnDeath=True
bEnableDLSS=False
bEnableDLFG=False
bEnableReflex=True
SuperResolutionQualityLevel=0
bOCIOIsEnabled=True
OCIOAsset=/Game/ASA/Environment/Common/Color/OCIO_aces_v13_cg.OCIO_aces_v13_cg
OCIOColorSpace=0
OCIODisplayView=0
bUseVSync=False
bUseDynamicResolution=False
ResolutionSizeX=1280
ResolutionSizeY=720
LastUserConfirmedResolutionSizeX=1280
LastUserConfirmedResolutionSizeY=720
WindowPosX=-1
WindowPosY=-1
FullscreenMode=1
LastConfirmedFullscreenMode=1
PreferredFullscreenMode=1
Version=5
AudioQualityLevel=0
LastConfirmedAudioQualityLevel=0
FrameRateLimit=60.000000
DesiredScreenWidth=1280
DesiredScreenHeight=720
LastUserConfirmedDesiredScreenWidth=1280
LastUserConfirmedDesiredScreenHeight=720
LastRecommendedScreenWidth=-1.000000
LastRecommendedScreenHeight=-1.000000
LastCPUBenchmarkResult=-1.000000
LastGPUBenchmarkResult=-1.000000
LastGPUBenchmarkMultiplier=1.000000
bUseHDRDisplayOutput=False
HDRDisplayOutputNits=1000

[/Script/Engine.GameUserSettings]
bUseDesiredScreenHeight=False

[SessionSettings]
SessionName=asa-sample-island
Port=7777
QueryPort=27015

[/Script/Engine.GameSession]
MaxPlayers=70
```

:::

:::details Game.ini

``` ini:Game.ini
[/script/shootergame.shootergamemode]
MatingIntervalMultiplier=0.25
BabyMatureSpeedMultiplier=4.0
EggHatchSpeedMultiplier=4.0
BabyCuddleIntervalMultiplier=0.025
BabyImprintAmountMultiplier=120.0
FuelConsumptionIntervalMultiplier=1.25
bPvEDisableFriendlyFire=True
bAllowUnlimitedRespecs=True
```

:::

### Startup Scriptの設定

Instanceの起動時に設定ファイルの取り込みとASA Serverの起動がしたいので、 [Startup Scritp](https://cloud.google.com/compute/docs/instances/startup-scripts/linux) を設定します。
Startup Scriptは [Instanceのメタデータ](https://cloud.google.com/compute/docs/metadata/overview) として、指定されたKeyを入れるとInstance起動時にshellを実行できる機能です。
メタデータ自体にshellの内容を全部書き込むパターンと、Cloud StorageのURLを書いて、そこにshellを置くパターンがあります。
筆者は更新が簡単なので、Cloud StorageのURLを書く方をよく使います。

Startup Scriptの中身はCloud Storageから設定ファイルをLocalにCopyし、ASA Serverを起動します。


```shell:startup.sh
#!/bin/bash

STEAMDIR="/home/steam/.local/share/Steam"
sudo -u steam gcloud storage cp gs://metal-ark-sample-config/island/GameUserSettings.ini "$STEAMDIR/steamapps/common/ARK Survival Ascended Dedicated Server/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini"
sudo -u steam gcloud storage cp gs://metal-ark-sample-config/island/Game.ini "$STEAMDIR/steamapps/common/ARK Survival Ascended Dedicated Server/ShooterGame/Saved/Config/WindowsServer/Game.ini"
sudo systemctl start ark-island
```

```shell:Startup Scriptを置くBucketの作成
gcloud storage buckets create gs://metal-ark-sample-shell -l asia-northeast1
```

```shell:Startup ScriptをCloud Storageにアップロード
gcloud storage cp startup.sh gs://metal-ark-sample-shell/island/startup.sh
```

```shell:InstanceのmetadataにStartup Scriptを設定
gcloud compute instances add-metadata asa-island --project $GOOGLE_CLOUD_PROJECT --zone asia-northeast1-b \
  --metadata=startup-script-url=gs://metal-ark-sample-shell/island/startup.sh
```

## Firewall-rule設定

Compute Engineには [Network Tag](https://cloud.google.com/vpc/docs/add-remove-network-tags) という機能があり、InstanceにこのTagを付けることで、Firewallを通す、通さないを制御することができます。
これを使えば通したい時だけ、通したいInstanceに到達させれるようになるので、筆者は好んで使っています。
今回は `ark` tagを付けたInstnaceが外から通信できるようにします。

```shell:ARK用Firewall Rule作成
gcloud compute --project=$GOOGLE_CLOUD_PROJECT firewall-rules create default-allow-ark --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=udp:7777-7778,udp:27015 --source-ranges=0.0.0.0/0 --target-tags=ark
```

```shell:Instanceにtagを追加
gcloud compute instances add-tags asa-island \
  --project=$GOOGLE_CLOUD_PROJECT \
  --zone asia-northeast1-b \
  --tags ark
```

Network構成については [ASAの日本語Wiki](https://wikiwiki.jp/arksa/%E3%82%B5%E3%83%BC%E3%83%90%E3%83%BC) にも書いてくれてる方がいるので、読んでみると良いかもしれません。

以下はARKサーバを動かすために必要な操作ではありませんが、やっておくとよさそうなことです。
最初から用意されているFirewall-ruleを修正しています。
ICMP, SSHに関してはtagが付いているInstanceだけ許可。
Remote Desktopは使わないので、削除しています。

やらなくても困りはしないのですが、ssh portは攻撃されたりして面倒なので、使わない時はFirewallで閉じておくのが無難です。

```shell:Firewall-ruleの調整
gcloud compute --project=$GOOGLE_CLOUD_PROJECT firewall-rules update default-allow-icmp --target-tags icmp
gcloud compute --project=$GOOGLE_CLOUD_PROJECT firewall-rules update default-allow-ssh --target-tags ssh
gcloud compute --project=$GOOGLE_CLOUD_PROJECT firewall-rules delete default-allow-rdp
```

## Scheduled Snapshotの設定

ARK: Survival Ascendedはアーリーアクセスということもあり、何が起こるか分かりません。
不足の事態に備え、日次でスナップショットを取っています。
UTCで指定するのでJSTのAM07:00である22:00にしています。

```shell:Snapshot Scheduleを作成
gcloud compute resource-policies create snapshot-schedule schedule-daily \
    --project=$GOOGLE_CLOUD_PROJECT \
    --region=asia-northeast1 \
    --max-retention-days=30 \
    --on-source-disk-delete=apply-retention-policy \
    --daily-schedule \
    --start-time=22:00 \
    --storage-location=asia-northeast1
```

```shell:DiskにSnaphost Scheduleを設定
gcloud compute disks add-resource-policies asa-island \
    --resource-policies schedule-daily \
    --project=$GOOGLE_CLOUD_PROJECT \
    --zone asia-northeast1-b
```

## 余談

コスト最適化を考えるともう少し改善する余地があると思っていますが、ひとまずこのぐらいで良いだろうと思っています。
後、やるとしたら、DiskはOSとASAが同じものに入っていて、まるごとスナップショットを作成しています。
OSの部分は必ずしも必要なものではないので、Diskを2つに分けてASA部分だけスナップショットを作成した方がコンパクトにはできるかもしれません。
ただ、Diskのスナップショットは差分だけが作られるので、毎日作成していたとしても、そこまで大きくはならないため、ひとまずやっていません。
