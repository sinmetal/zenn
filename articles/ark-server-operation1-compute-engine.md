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
同じことをしたい人はあまりいないとは思いますが、どのような構成になっているかを記しておきます。
長くなるので、いくつかのレイヤーに分けて記事を書いていこうと思います。
この記事は1つ目です。

* その1 Compute EngineでServerを動かす
* その2 サーバの起動と自動停止を行うDiscord BotとAgent
* その3 生物のステータスをBigQueryで整理する

## Compute Engine Insntaceの作成

まずはCompute EngineのInstanceで利用するService Accountを作ります。
Defaultで用意されているCompute Engine Default Service Account使っても良いのですが、自分はあのService Accountを使うのはあまり好きではないので、個別に作ります。
[Service Accountの運用について](https://github.com/gcpug/nouhau/tree/master/general/note/destroy-service-account-key)

RoleとしてCloud StorageへのアクセスやOperation SuiteへのWriteを付けておきます。
Cloud StorageへのアクセスはBucketごとに真面目に設定した方が本当は良いですが、適当にProject Levelで付けてます。

```
gcloud iam service-accounts create ark-server --description="ARK Server Worker" --display-name="ark-server"
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT --member=serviceAccount:ark-server@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role=roles/storage.admin
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT --member=serviceAccount:ark-server@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role=roles/logging.logWriter
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT --member=serviceAccount:ark-server@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com --role=roles/monitoring.metricWriter
```

Service Accountが作れたら、Instanceを作ります。
ASAはメモリが16GB弱使うのでマシンタイプは `e2-highmem-2` を使い、Diskは50GBのBalanced Persistent Diskを使っています。
それ以外はほぼdefaultのままです。

```
export GOOGLE_CLOUD_PROJECT=metal-ark-sample-20231207

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
ただ、Install後いくつか変えている部分があります。

`GameUserSettings.ini` のシンボリックリンクが貼られているのですが、自分はサーバ上で編集するのではなく、GitHub上で管理したいので、外からアップロードするので、シンボリックリンクは削除します。

```
sudo unlink /home/steam/island-GameUserSettings.ini
```

### GameSettings Fileの準備

ARKでは `GameUserSettings.ini` と `Game.ini` の2つの設定ファイルがあるので、どちらも用意します。
主にゲームバランスに関する設定ですが、いくつかサーバ管理のための値があります。
以下の2つは後でFirewallの設定をする時に使います。
設定しなくてもdefaultの値があると思うのですが、筆者はdefaultの値が分からなかったので、明示的に設定しています。

* Port=7805
* QueryPort=27030

ファイルが作成できたら、Cloud Storageにアップロードしておきます。
筆者はGitHubで管理しているので、 [Cloud Build Trigger](https://cloud.google.com/build/docs/triggers) を利用して、BranchがPushされたら、Cloud Storageにアップロードするようにしています。

Bucketの作成

```
gcloud storage buckets create gs://metal-ark-sample-config -l asia-northeast1
```

ファイルのアップロード

```
gcloud storage cp GameUserSettings.ini gs://metal-ark-sample-20231207-config/island/GameUserSettings.ini
gcloud storage cp Game.ini gs://metal-ark-sample-20231207-config/island/Game.ini
```

以下は筆者の設定ファイルのサンプルです。
参考程度にどうぞ。
もし真似する場合は以下の2つは必ず変更が必要です。

* `SessionName=asa-sample-island2` : Server検索時に出てくる名前なので、好きな名前に変更します。
* `ServerAdminPassword=xxxxxxxx` : 管理者コマンド用パスワードなので、好きな値に変更します。

GameUserSettings.ini

```
[ServerSettings]
ServerAdminPassword=xxxxxxxx
ServerPVE=True
ShowMapPlayerLocation=True
AllowThirdPersonPlayer=True
ServerCrosshair=True
RCONPort=27036
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
KickIdlePlayersPeriod=7200
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
SessionName=asa-sample-island2
Port=7805
QueryPort=27030

[/Script/Engine.GameSession]
MaxPlayers=70
```


Game.ini

```
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

### Startup Scriptの設定

Instanceの再起動時に設定ファイルを取り込みたいので、 [Startup Scritp](https://cloud.google.com/compute/docs/instances/startup-scripts/linux) を設定します。
Startup Scriptは [Instanceのメタデータ](https://cloud.google.com/compute/docs/metadata/overview) として、指定されたKeyを入れるとInstance起動時にshellを実行できる機能です。
メタデータ自体にshellの内容を全部書き込むパターンと、Cloud StorageのURLを書いて、そこにshellを置くパターンがあります。
筆者は更新が簡単なので、Cloud StorageにURLを書く方をよく使います。

Startup Scriptを置くBucketの作成

```
gcloud storage buckets create gs://metal-ark-sample-shell -l asia-northeast1
```

```
gcloud storage cp startup.sh gs://metal-ark-sample-20231207-shell/island/startup.sh
```

startup.sh

Cloud Storageから2つの設定ファイルをコピーした後、サーバを起動します。

```
#!/bin/bash

STEAMDIR="/home/steam/.local/share/Steam"
sudo -u steam gcloud storage cp gs://metal-ark-sample-config/island/GameUserSettings.ini "$STEAMDIR/steamapps/common/ARK Survival Ascended Dedicated Server/ShooterGame/Saved/Config/WindowsServer/GameUserSettings.ini"
sudo -u steam gcloud storage cp gs://metal-ark-sample-config/island/Game.ini "$STEAMDIR/steamapps/common/ARK Survival Ascended Dedicated Server/ShooterGame/Saved/Config/WindowsServer/Game.ini"
sudo systemctl start ark-island
```

```
gcloud compute instances add-metadata asa-island --project metal-ark-sample-20231207 --zone asia-northeast1-b \
  --metadata=startup-script-url=gs://metal-ark-sample-20231207-shell/island/startup.sh
```

## Firewall設定

```
gcloud compute --project=metal-ark-sample-20231207 firewall-rules create default-allow-ark --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:7777-7805,tcp:27030,udp:7777-7805,udp:27030 --source-ranges=0.0.0.0/0 --target-tags=ark
```

```
gcloud compute instances add-tags asa-island \
  --project=metal-ark-sample-20231207 \
  --zone asia-northeast1-b \
  --tags ark
```

## Scheduled Snapshotの設定

```
gcloud compute resource-policies create snapshot-schedule schedule-daily \
    --project=metal-ark-sample-20231207 \
    --region=asia-northeast1 \
    --max-retention-days=30 \
    --on-source-disk-delete=apply-retention-policy \
    --daily-schedule \
    --start-time=22:00 \
    --storage-location=asia-northeast1
```