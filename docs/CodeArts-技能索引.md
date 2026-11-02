# CodeArts · Godot 技能索引（154 个）
> 源目录：`D:\zcode-work\godot\.zcode\skills\<技能名>\SKILL.md`（本索引是快照，源目录为准）
> 用法：**按任务查表，只读需要的那个 SKILL.md 全文**；不要一次全读。技能里的命令先在 Godot 4.7.2 上验证再落地。

## 最常用的 12 个（先读这些）
| 技能 | 用途 |
|---|---|
| `gd-headless-testing` | 无头确定性测试：SceneTree 脚本、帧计数断言、CI 可跑 |
| `gd-export-selfcontained` | 自包含导出：Windows exe / pck / 资源过滤 |
| `gd-monte-carlo-balancer` | 蒙特卡洛平衡：批量模拟、分位数、目标分反推 |
| `gd-genre-roguelike` | 肉鸽设计：节点、奖励、风险收益、重开循环 |
| `gd-godot-ui` | Godot UI：Control 布局、主题、容器、分辨率适配 |
| `gd-tween-animation` | Tween 动效：UI 滑入滑出、缓动、序列动画 |
| `gd-asset-gen` | 资产生成：生图、抠图、切件、导入设置 |
| `gd-assets-pipeline` | 资产管线：命名、目录、导入、版本管理 |
| `gd-agent-vision` | 截图目检：headless 截图钩子 + 视觉模型验界面 |
| `gd-godot-debugging` | Godot 调试：断点、性能、常见崩溃定位 |
| `gd-gdscript-mastery` | GDScript 进阶：类型、信号、生命周期、陷阱 |
| `gd-save-load` | 存档：JSON/Resource 持久化、版本迁移 |

## 按任务选技能
| 你要做的事 | 先读 |
|---|---|
| 写/改自动化测试 | `gd-headless-testing`、`gd-testing-patterns` |
| 打包 Windows exe | `gd-export-selfcontained`、`gd-export-pipeline` |
| 调数值/关卡平衡 | `gd-monte-carlo-balancer`、`gd-economy-system` |
| 做卡牌/回合制玩法 | `gd-genre-card-game`、`gd-turn-system`、`gd-combat-system` |
| 做 UI/卡面/布局 | `gd-godot-ui`、`gd-ui-theming`、`gd-ui-containers` |
| 做动效/转场/抖动 | `gd-tween-animation`、`gd-2d-animation`、`gd-particles-vfx` |
| 出图/抠图/切立绘 | `gd-asset-gen`、`gd-assets-pipeline` |
| 截图检查界面 | `gd-agent-vision` |
| 查崩溃/性能 | `gd-godot-debugging`、`gd-performance-optimization` |
| 存档/跨局进度 | `gd-save-load`、`gd-resource-data-patterns` |
| 音频/音效 | `gd-audio-system`、`gd-audio-systems` |

## 全量索引（按字母序）
| 技能 | 官方描述（截断） |
|---|---|
| `gd-2d-animation` | Expert patterns for 2D animation in Godot using AnimatedSprite2D and skeletal cutout rigs. Use when implementing sprite frame animations, procedural animation (squash/stretch), cutout bone hierarchies, or frame-perfect timing s… |
| `gd-2d-essentials` | Use when working with 2D-specific systems — TileMaps, parallax scrolling, 2D lights and shadows, canvas layers, particles 2D, custom drawing, and 2D meshes in Godot 4.3+ |
| `gd-2d-physics` | Expert patterns for Godot 2D physics including collision layers/masks, Area2D triggers, raycasting, and PhysicsDirectSpaceState2D queries. Use when implementing collision detection, trigger zones, line-of-sight systems, or manu… |
| `gd-3d-essentials` | Use when working with 3D-specific systems — materials, lighting, shadows, environment, global illumination, fog, LOD, occlusion culling, and decals in Godot 4.3+ |
| `gd-3d-lighting` | Expert patterns for Godot 3D lighting including DirectionalLight3D shadow cascades, OmniLight3D attenuation, SpotLight3D projectors, VoxelGI vs SDFGI, and LightmapGI baking. Use when implementing realistic 3D lighting, shadow o… |
| `gd-3d-materials` | Expert patterns for Godot 3D PBR materials using StandardMaterial3D including albedo, metallic/roughness workflows, normal maps, ORM texture packing, transparency modes, and shader conversion. Use when creating realistic 3D sur… |
| `gd-3d-world-building` | Expert patterns for 3D level design using GridMap with MeshLibrary, CSG constructive solid geometry, occlusion, and runtime GridMap builders. Use when building 3D levels, modular tilesets, or BSP-style geometry. For sky/fog/Env… |
| `gd-ability-system` | Expert patterns for RPG/action ability systems including cooldown strategies, combo systems, ability chaining, skill trees with prerequisites, upgrade paths, and resource management. Use when implementing unlockable abilities,… |
| `gd-action-combat-2d` | Expert patterns for 2D side-scrolling action combat (Hollow Knight / Castlevania style): layered state machine for player attacks, input buffering, hitbox/hurtbox damage pipeline with i-frames, knockback by damage source direct… |
| `gd-adapt-2d-to-3d` | Expert patterns for migrating 2D games to 3D including node type conversions, camera systems (third-person, first-person, orbit), physics layer migration, sprite-to-model art pipeline, and control scheme adaptations. Use when p… |
| `gd-adapt-3d-to-2d` | Expert patterns for simplifying 3D games to 2D including dimension reduction strategies, 2.5D fake-depth, isometric ports, camera flattening, physics conversion, 3D-to-sprite art pipeline, and control simplification. Use when p… |
| `gd-adapt-desktop-to-mobile` | Expert patterns for porting desktop games to mobile including touch control schemes (virtual joystick, gesture detection), UI scaling for small screens, performance optimization for mobile GPUs, battery life management, and pla… |
| `gd-adapt-mobile-to-desktop` | Expert patterns for scaling mobile games to desktop including mouse/keyboard controls, increased resolution and graphical fidelity, expanded UI layouts, settings menus, window management, and platform-specific features. Use whe… |
| `gd-adapt-single-to-multiplayer` | Expert patterns for adding multiplayer to single-player games including client-server architecture, authoritative server design, MultiplayerSynchronizer, lag compensation (client prediction, server reconciliation), input buffer… |
| `gd-addon-development` | Use when creating Godot editor plugins — EditorPlugin, @tool scripts, custom inspectors, and dock panels |
| `gd-agent-vision` | Agentic eyes for Godot work: cross-platform screenshot CLI (asset/region/window/screen) to budgeted WebP, TEMP editor viewport bridge under .gdskills/, and Taste Receptor Atlas v2 (~237 micro-receptors × 0–2: hierarchy, contras… |
| `gd-ai-navigation` | AI movement decision router for chase, patrol, crowd, and bake choices on top of NavigationAgent/Server. Use when deciding node agent vs RID server, bake vs obstacle, layer masks, or retarget policy — not for engine navmesh rec… |
| `gd-analyst` | Godot Expert Analyst: Anara. Visionary project scoring and certification for Godot 4.7+ architecture. Use when evaluating project health, modernity, scalability, dependency graphs, or generating Visionary Certificates. Keywords… |
| `gd-animation-player` | Expert patterns for AnimationPlayer including track types (Value, Method, Audio, Bezier), root motion extraction, animation callbacks, procedural animation generation, call mode optimization, and RESET tracks. Use for timeline-… |
| `gd-animation-system` | Use when implementing animations — AnimationPlayer, AnimationTree, blend trees, state machines, sprite animation, and code-driven animation |
| `gd-animation-tree-mastery` | Expert patterns for AnimationTree including StateMachine transitions, BlendSpace2D for directional movement, BlendTree for layered animations, root motion, transition conditions, advance expressions, and state machine sub-state… |
| `gd-asset-gen` | Generate visual assets from text prompts: PNG images (Gemini / xAI Grok), GLB 3D models (Tripo3D), rigged biped characters, retargeted animations, and frame-by-frame animated sprites, plus background removal. Use whenever a gam… |
| `gd-assets-pipeline` | Use when importing and managing assets — image compression, 3D scene import, audio formats, resource formats, and import configuration |
| `gd-audio-system` | Use when implementing audio — audio buses, AudioStreamPlayer, spatial audio, music management, SFX pooling, and dynamic mixing |
| `gd-audio-systems` | Expert patterns for Godot audio including AudioStreamPlayer variants (2D positional, 3D spatial), AudioBus mixing architecture, dynamic effects (reverb, EQ,compression), audio pooling for performance, music transitions (crossfa… |
| `gd-auditor` | Godot Expert Auditor: Aurelius. Exhaustive never-list enforcement and architectural slap-down for Godot 4.7 projects. Use when auditing signal decay, ObjectDB orphans, typed Array/Dictionary slop, material.duplicate batch break… |
| `gd-autoload-architecture` | Expert patterns for Godot AutoLoad (singleton) architecture including global state management, scene transitions, signal-based communication, dependency injection, autoload initialization order, and anti-patterns to avoid. Use… |
| `gd-beehave` | Use when using the Beehave addon — pure-GDScript behavior trees with composites, decorators, leaves, a blackboard, and a visual runtime debugger |
| `gd-builder` | Expert-level toolkit for modular Godot 4.7+ CLI automation and headless build orchestration. Use when you need to: (1) Build complex scene trees or UI layouts programmatically, (2) Automate expert 3D asset pipelines (glTF -> Co… |
| `gd-camera-system` | Use when implementing cameras — smooth follow, screen shake, camera zones, and transitions for 2D and 3D |
| `gd-camera-systems` | Expert patterns for 2D/3D camera control including smooth following (lerp, position_smoothing), camera shake (trauma system), screen shake with frequency parameters, deadzone/drag for platformers, look-ahead prediction, and cam… |
| `gd-characterbody-2d` | Expert patterns for CharacterBody2D including platformer movement (coyote time, jump buffering, variable jump height), top-down movement (8-way, tank controls), collision handling, one-way platforms, and state machines. Use for… |
| `gd-combat-system` | Expert patterns for combat systems including hitbox/hurtbox architecture, damage calculation (DamageData class), health components, combat state machines, combo systems, ability cooldowns, and damage popups. Use for action game… |
| `gd-component-system` | Use when building reusable node components — composition patterns, component communication, and interface design |
| `gd-composition` | Expert architectural standards for building scalable Godot GAMES (RPGs, Platformers, Shooters) using the Composition pattern (Entity-Component). Use when designing player controllers, NPCs, enemies, weapons, or complex gameplay… |
| `gd-composition-apps` | Expert architectural standards for scalable Godot Apps, Tools, EditorPlugins, and Control-heavy UIs using Composition (Has-A Orchestrator + components). Use when building dashboards, tool windows, forms, settings panels, or Edi… |
| `gd-csharp-godot` | Use when working with C# in Godot — conventions, GodotSharp API differences from GDScript, project setup, and interop |
| `gd-csharp-signals` | Use when implementing signals in C# — [Signal] delegates, EmitSignal patterns, async signal awaiting, and event-driven architecture |
| `gd-debugging-profiling` | Expert debugging and profiling for leaks, GPU/Visual Profiler, headless CI QA, orphan nodes, thread-safe logs, and custom Debugger monitors — not print/breakpoint tutorials. Trigger on OBJECT_ORPHAN_NODE_COUNT, ObjectDB growth,… |
| `gd-dedicated-server` | Use when building dedicated servers — headless export, server architecture, lobby management, and deployment |
| `gd-dependency-injection` | Use when managing dependencies between systems — autoloads, service locators, @export injection, and scene injection patterns |
| `gd-dialogue-manager` | Use when using the Dialogue Manager addon — .dialogue files with titles, responses, conditions and mutations, runtime balloons, and C# support |
| `gd-dialogue-system` | Expert patterns for branching dialogue systems including dialogue graphs (Resource-based), character portraits, player choices, conditional dialogue (flags/quests), typewriter effects, localization support, and voice acting int… |
| `gd-economy-system` | Expert patterns for game economies including currency management (multi-currency, wallet system), shop systems (buy/sell prices, stock limits), dynamic pricing (supply/demand), loot tables (weighted drops, rarity tiers), and ec… |
| `gd-event-bus` | Use when implementing decoupled communication between nodes — global EventBus autoload with typed signals |
| `gd-export-builds` | Expert patterns for multi-platform exports including export templates (Windows/Linux/macOS/Android/iOS/Web), command-line exports (headless mode), platform-specific settings (codesign, notarization, Android SDK), feature flags… |
| `gd-export-pipeline` | Use when exporting and distributing Godot games — export presets, platform settings, CI/CD with GitHub Actions |
| `gd-export-selfcontained` | D-drive green export pipeline for Godot 4.7 on this machine: self-contained mode (._sc_), export templates location, headless --export-release commands, and the three-layer junction layout. Use when exporting a Godot game to ex… |
| `gd-game-loop-collection` | Expert collection-loop systems for collectible IDs, scavenger hunts, completion archives, nearest-item compass UI, hidden spawners, and persistent find-all-X progress. Use when implementing collectibles, scavenger hunts, comple… |
| `gd-game-loop-harvest` | Data-driven resource harvesting (mining, logging, foraging) for Godot 4: apply_hit tool/tier validation via HarvestToolData enums, HarvestResourceData yields, harvestable_node shake/deplete, respawn_manager world persistence, U… |
| `gd-game-loop-time-trial` | Expert patterns for racing mechanics, checkpoint tracking, and ghost recording/playback in Godot 4. Use when building racing games, speed-run platformers, or arcade trials. |
| `gd-game-loop-waves` | Expert patterns for managing combat waves, difficulty scaling, and automated enemy spawning in Godot 4. Use when building wave-based shooters, tower defense, or arena games. |
| `gd-gdextension` | Use when building native extensions for Godot — godot-cpp (C++) or gdext (Rust), binding classes, building, and GDScript/C# interop |
| `gd-gdscript-advanced` | Use when writing production-grade GDScript — performance idioms, metaprogramming, @tool lifecycle, async pitfalls, signal/Callable trade-offs, profiler-driven idioms, and common pitfalls |
| `gd-gdscript-mastery` | Expert GDScript landmine guidance: static typing opcodes, signal-up/call-down, %UniqueName/@onready lifecycle, Callable bind/unbind, await sequences, typed collections, and safe Dictionary iteration. Use for code review, refact… |
| `gd-gdscript-patterns` | Use when writing GDScript — static typing, await/coroutines, lambdas, match patterns, export annotations, inner classes, and common idioms |
| `gd-gdunit4-testing` | Develop, test, build, and deploy Godot 4.x games. Includes GdUnit4 for GDScript unit tests (headless CLI, scene runner, input simulation) and PlayGodot for game automation / E2E testing. Supports web/desktop exports, CI/CD pipe… |
| `gd-genre-action-rpg` | Comprehensive blueprint for Action RPGs including real-time combat (hitbox/hurtbox, stat-based damage), character progression (RPG stats, leveling, skill trees), loot systems (procedural item generation, affixes, rarity tiers),… |
| `gd-genre-battle-royale` | Expert blueprint for Battle Royale games including shrinking zone/storm mechanics (phase-based, damage scaling), large-scale networking (relevancy, tick rate optimization), deployment systems (plane, freefall, parachute), loot… |
| `gd-genre-card-game` | Expert blueprint for digital card games (CCG/Deckbuilders) including card data structures (Resource-based), deck management (draw/discard/reshuffle), turn logic, hand layout (arcing), drag-and-drop UI, effect resolution (Comman… |
| `gd-genre-educational` | Expert blueprint for educational games including gamification loops (learn/apply/feedback/adapt), progress tracking (student profiles, mastery %), adaptive difficulty (target 70% success rate), spaced repetition, curriculum tre… |
| `gd-genre-fighting` | Expert blueprint for fighting games including frame data (startup/active/recovery frames, advantage on hit/block), hitbox/hurtbox systems, input buffering (5-10 frames), motion input detection (QCF, DP), combo systems (damage s… |
| `gd-genre-horror` | Expert blueprint for horror games: sawtooth tension pacing, Director macro-AI, sensory predator AI, sanity/stress FX, and scarcity loops. Use when building psychological/survival horror, dual-brain stalker AI (cheating Director… |
| `gd-genre-idle-clicker` | Expert blueprint for idle/clicker games including big number handling (mantissa + exponent system), exponential growth curves (cost_growth_factor 1.15x), generator systems (auto-producers), offline progress calculation, prestig… |
| `gd-genre-metroidvania` | Expert blueprint for Metroidvanias including ability-gated exploration (locks/keys), interconnected world design (backtracking with shortcuts), persistent state tracking (collectibles, boss defeats), room transitions (seamless… |
| `gd-genre-moba` | Expert blueprint for MOBA games including lane logic (minion wave spawning every 30s), tower aggro priority (hero attacking ally over minion over hero), click-to-move controls (RTS-style raycasting), hero ability systems (QWER… |
| `gd-genre-open-world` | Expert blueprint for open world games including chunk-based streaming (load/unload regions dynamically), floating origin (prevent precision jitter beyond 5000 units), HLOD (hierarchical LOD for distant meshes), persistent state… |
| `gd-genre-party` | Expert blueprint for party games including minigame resource system (define via .tres files), local multiplayer input (4-player controller management), asymmetric gameplay (1v3 balance), scene management (clean minigame loading… |
| `gd-genre-platformer` | Expert blueprint for platformer games including precision movement (coyote time, jump buffering, variable jump height), game feel polish (squash/stretch, particle trails, camera shake), level design principles (difficulty curve… |
| `gd-genre-puzzle` | Expert blueprint for puzzle games including undo systems (Command pattern for state reversal), grid-based logic (Sokoban-style mechanics), non-verbal tutorials (teach through level design), win condition checking, state managem… |
| `gd-genre-racing` | Expert blueprint for racing games including vehicle physics (VehicleBody3D, suspension, friction), checkpoint systems (prevent shortcuts), rubber-banding AI (keep races competitive), drifting mechanics (reduce friction, boost o… |
| `gd-genre-rhythm` | Expert blueprint for rhythm games including audio synchronization (BPM conductor, latency compensation with AudioServer.get_time_since_last_mix), note highways (scroll speed, timing windows), judgment systems (Perfect/Great/Goo… |
| `gd-genre-roguelike` | Expert blueprint for roguelikes including procedural generation (Walker method, BSP rooms), permadeath with meta-progression (unlock persistence), run state vs meta state separation, seeded RNG (shareable runs), loot/relic syst… |
| `gd-genre-romance` | Expert blueprint for romance games and dating sims (Tokimeki Memorial, Monster Prom, Persona social links) focusing on affection systems, multi-stat relationships, dated events, and route branching. Use when building relationsh… |
| `gd-genre-rts` | Expert blueprint for real-time strategy games including unit selection (drag box, shift-add), command systems (move, attack, gather), pathfinding (NavigationAgent2D with RVO avoidance), fog of war (SubViewport mask shader), res… |
| `gd-genre-sandbox` | Expert blueprint for sandbox games (Minecraft, Terraria, Garry's Mod) with physics-based interactions, cellular automata, emergent gameplay, and creative tools. Use when building open-world creation games with voxels, element s… |
| `gd-genre-shooter` | Expert blueprint for TPS/hybrid shooters: soft-lock aim assist, cover validation rays, SpringArm TPS camera, and genre routing to FPS sibling for viewmodel/hitscan feel. Use for third-person/cover shooters and hybrids. Keywords… |
| `gd-genre-shooter-fps` | Expert blueprint for First-Person Shooters: fps_camera_look, fps_movement_logic, hitscan_weapon_query, weapon_bobbing_system, procedural recoil, and FPS NEVER rules. Shared TPS/cover theory links to godot-genre-shooter. Keyword… |
| `gd-genre-simulation` | Expert blueprint for simulation and tycoon games (SimCity, RollerCoaster Tycoon, Factorio, Two Point Hospital) covering economy management, time progression, interconnected systems, NPC simulation, and feedback loops. Use when… |
| `gd-genre-sports` | Expert blueprint for sports games (FIFA, NBA 2K, Rocket League, Tony Hawk) covering physics-based ball interaction, team AI formations, contextual input, and match umpire/score authority. Broadcast framing routes to godot-camer… |
| `gd-genre-stealth` | Expert blueprint for stealth games (Splinter Cell, Hitman, Dishonored, Thief) covering AI detection systems, vision cones, sound propagation, alert states, light/shadow mechanics, and systemic design. Use when building stealth-… |
| `gd-genre-survival` | Expert blueprint for survival games (Minecraft, Don't Starve, The Forest, Rust) covering needs systems, resource gathering, crafting recipes, base building, and progression balancing. Use when building open-world survival, craf… |
| `gd-genre-tower-defense` | Expert blueprint for tower defense games (Bloons TD, Kingdom Rush, Fieldrunners) covering wave management, tower targeting logic, path algorithms, economy balance, and mazing mechanics. Use when building TD, lane defense, or to… |
| `gd-genre-visual-novel` | Expert blueprint for visual novels (Doki Doki Literature Club, Phoenix Wright, Steins;Gate) focusing on branching narratives, dialogue systems, choice consequences, rollback mechanics, and persistent flags. Use when building st… |
| `gd-godot-brainstorming` | Use when designing a new Godot feature or system — guides scene tree planning, node type selection, and architectural decisions |
| `gd-godot-code-review` | Use when reviewing GDScript or C# Godot code — checklist of best practices, common anti-patterns, and Godot-specific pitfalls |
| `gd-godot-debugging` | Use when debugging Godot projects — remote debugger, print techniques, signal tracing, common error patterns and fixes |
| `gd-godot-mentor` | Use when the user wants to learn Godot while building — teaching mode that explains the concept, the editor setup, and what to verify, instead of just delivering code. Triggers on "teach me", "explain as we go", "I'm learning G… |
| `gd-godot-optimization` | Use when optimizing Godot games — profiler, draw calls, physics tuning, memory management, and common bottlenecks |
| `gd-godot-project-setup` | Use when creating a new Godot 4.x project — scaffolds recommended directory structure, project settings, autoloads, and .gitignore |
| `gd-godot-testing` | Use when writing tests for Godot projects — TDD workflow with GUT and gdUnit4, covers both GDScript and C# |
| `gd-godot-ui` | Use when building user interfaces — Control nodes, themes, anchors, containers, and layout patterns |
| `gd-headless-testing` | Deterministic headless smoke testing for Godot 4.x projects: SceneTree test scripts with physics_frame-counted assertions, manually-triggered callbacks instead of real-time waits, RigidBody3D teleportation inputs. Use when writ… |
| `gd-hud-system` | Use when building in-game HUDs — health bars, score displays, minimap, notifications, and damage numbers |
| `gd-input-handling` | Expert patterns for input handling covering InputMap actions, InputEvent processing, controller support, rebinding, deadzones, and input buffering. Use when setting up player controls, implementing input systems, or adding game… |
| `gd-inventory-system` | Expert blueprint for inventory systems (Diablo, Resident Evil, Minecraft) covering slot-based containers, stacking logic, weight limits, equipment systems, and drag-drop UI. Use when building RPG inventories, survival item mana… |
| `gd-limboai` | Use when using the LimboAI addon — behavior trees and hierarchical state machines (C++ GDExtension) with a visual editor, BTTask subclassing, and a blackboard |
| `gd-localization` | Use when implementing localization (i18n/l10n) — TranslationServer, CSV/PO translation files, locale switching, RTL support, and pluralization in Godot 4.3+ |
| `gd-master` | Consolidated expert library for professional Godot 4.7+ game and application development. Orchestrates 92 Domain Skills through architectural workflows, anti-pattern catalogs, performance budgets, and Server API patterns. Use w… |
| `gd-math-essentials` | Use when implementing game math — vectors, transforms, interpolation, curves, random number generation, and common geometric recipes |
| `gd-mechanic-revival` | Expert blueprint for player mortality loops: progress-index checkpoints, soul graves, ghost/spirit layers, I-frame restitution, world-progress persistence, and death analytics. Use when implementing respawn, shrine checkpoints,… |
| `gd-mechanic-secrets` | Implement cheat codes, hidden interactions, and unlockable meta-content via time-windowed input sequence buffers, spam thresholds, look-at (dot-product) detectors, progress-% unlocks, and meta persistence in user://secrets.cfg.… |
| `gd-mobile-development` | Use when targeting Android/iOS — export and signing, permissions, plugins, in-app purchases, ads, app lifecycle, device features, and mobile performance |
| `gd-monte-carlo-balancer` | Use when auditing or recalibrating game balance: build a source-driven Monte Carlo balance lab (Rust + rayon) that extracts live game data, simulates human playstyles (AFK→pro), emits win-rate/economy verdicts with confidence i… |
| `gd-multiplayer-basics` | Use when implementing multiplayer — MultiplayerAPI, ENet/WebSocket peers, RPCs, and authority model |
| `gd-multiplayer-networking` | Expert multiplayer for desync, rollback, dedicated --headless servers, interest culling, and bandwidth spikes: ENet/WebRTC choice, authority, secure RPCs, client prediction/reconcile, and adaptive sync. Trigger on rubber-bandin… |
| `gd-multiplayer-sync` | Use when synchronizing multiplayer state — MultiplayerSynchronizer, interpolation, prediction, and lag compensation |
| `gd-multithreading` | Use when running work off the main thread — WorkerThreadPool, Thread/Mutex/Semaphore, call_deferred, thread-safe scene access, and threaded resource loading |
| `gd-navigation-pathfinding` | Expert blueprint for AI pathfinding (tower defense, RTS, stealth) using NavigationAgent2D/3D, NavigationServer, avoidance, and dynamic navigation mesh generation. Use when implementing enemy AI, NPC movement, or obstacle avoida… |
| `gd-particles` | Expert blueprint for GPU particle systems (explosions, magic effects, weather, trails) using GPUParticles2D/3D, ParticleProcessMaterial, gradients, sub-emitters, and custom shaders. Use when creating VFX, environmental effects,… |
| `gd-particles-vfx` | Use when implementing particle effects — GPUParticles2D/3D, ParticleProcessMaterial, emission shapes, subemitters, trails, attractors, collision, and common VFX recipes |
| `gd-performance-optimization` | Expert blueprint for performance profiling and optimization (frame drops, memory leaks, draw calls) using Godot Profiler, object pooling, visibility culling, and bottleneck identification. Use when diagnosing lag, optimizing fo… |
| `gd-phantom-camera` | Use when using the Phantom Camera addon — PhantomCamera2D/3D with priority-based switching, follow and look-at modes, and tween transitions |
| `gd-physics-3d` | Expert patterns for Godot 3D physics (Jolt/PhysX), including Ragdolls, PhysicalBones, Joint3D constraints, RayCasting optimizations, and collision layers. Use for rigid body simulations, character physics, or complex interactio… |
| `gd-physics-system` | Use when working with physics bodies, collision shapes, raycasting, areas, rigid bodies, ragdolls, soft bodies, Jolt physics, and physics interpolation in Godot 4.3+ |
| `gd-platform-console` | Expert blueprint for console platforms (PlayStation, Xbox, Nintendo Switch) covering controller-first UI, certification requirements (TRCs/TCRs), platform services (achievements, cloud saves), and performance compliance. Use wh… |
| `gd-platform-desktop` | Expert blueprint for desktop platforms (Windows/Linux/macOS) covering keyboard/mouse controls, settings menus, window management (fullscreen, resolution), keybind remapping, and Steam integration. Use when targeting PC platform… |
| `gd-platform-mobile` | Expert blueprint for mobile platforms (Android/iOS) covering touch controls, virtual joysticks, responsive UI, safe areas (notches), battery optimization, and app store guidelines. Use when targeting mobile releases or implemen… |
| `gd-platform-vr` | Expert blueprint for VR platforms (Meta Quest, PSVR, SteamVR, Pico) covering XR toolkit (OpenXR), comfort settings (vignetting, snap turning, teleport), motion controls, hand tracking, and 90+ FPS requirements. Use when targeti… |
| `gd-platform-web` | Expert blueprint for HTML5/web export on Compatibility (WebGL 2.0): JavaScriptBridge, localStorage wrapper, custom loading shells, COOP/COEP hosts, relative paths, beforeunload, visibility pause, and size optimization. WebGPU i… |
| `gd-player-controller` | Use when implementing player movement — CharacterBody2D/3D patterns, input handling, physics, common movement recipes |
| `gd-popochiu` | Use when using the Popochiu addon — point-and-click adventure framework with rooms, characters, props/hotspots, inventory, dialog trees, and a command-based GUI |
| `gd-procedural-generation` | Expert blueprint for procedural content generation (dungeons, terrain, loot, levels) using FastNoiseLite, random walks, BSP trees, Wave Function Collapse, and seeded randomization. Use when creating roguelikes, sandbox games, o… |
| `gd-project-foundations` | Expert blueprint for Godot 4 project organization (feature-based folders, naming conventions, version control). Enforces snake_case files, PascalCase nodes, %SceneUniqueNames, and .gitignore best practices. Use when starting ne… |
| `gd-project-scaffold` | Standard Godot 4.x project scaffold discipline for this workspace: project.godot input maps, directory layout, the three-piece doc set (handover/pitfall-log/smoke-test), D-drive rules, and the --editor launch pitfall. Use when… |
| `gd-project-templates` | Navigation skill for genre project scaffolds: pick platformer/RPG/FPS (or other genre) then load matching template scripts and route gameplay fill to godot-genre-* skills. Use when bootstrapping architecture, bootstrap order, p… |
| `gd-quest-system` | Expert blueprint for quest tracking systems (objectives, progress, rewards, branching chains) using Resource-based quests, signal-driven updates, and AutoLoad managers. Use when implementing RPG quests or mission systems. Keywo… |
| `gd-raycasting-queries` | Expert blueprint for physics queries using RayCast, ShapeCast, and DirectSpaceState. Covers hit detection, volume overlap, mouse picking, and high-performance server-side intersection queries. Use when implementing projectiles,… |
| `gd-resource-data-patterns` | Expert blueprint for data-oriented design using Resource/RefCounted classes (item databases, character stats, reusable data structures). Covers typed arrays, serialization, nested resources, and resource caching. Use when imple… |
| `gd-resource-pattern` | Use when creating data containers in Godot — custom Resources for configuration, items, stats, and editor integration |
| `gd-responsive-ui` | Use when handling multiple resolutions — stretch modes, aspect ratios, DPI scaling, and mobile/desktop adaptation |
| `gd-rpg-stats` | Expert blueprint for RPG stat systems (attributes, leveling, modifiers, damage formulas) using Resource-based stats, stackable modifiers, and derived stat calculations. Use when implementing character progression OR equipment/b… |
| `gd-save-load` | Use when implementing save/load systems — ConfigFile, JSON, Resource serialization, save game architecture |
| `gd-save-load-systems` | Expert blueprint for save/load systems using JSON/binary serialization, PERSIST group pattern, versioning, and migration. Covers player progress, settings, game state persistence, and error recovery. Use when implementing save… |
| `gd-scene-management` | Expert blueprint for scene loading, transitions, async (background) loading, instance management, and caching. Covers fade transitions, loading screens, dynamic spawning, and scene persistence. Use when implementing level chang… |
| `gd-scene-organization` | Use when designing scene tree structure — composition vs inheritance, when to split scenes, node hierarchy patterns |
| `gd-server-architecture` | Expert blueprint for dedicated / headless multiplayer hosts: ENet/DTLS, authority validation, safe packet decode, matchmaker handoff, and health telemetry. Use when building authoritative servers, --headless hosts, or hardening… |
| `gd-shader-basics` | Use when implementing shaders — Godot shader language, visual shaders, common visual recipes, and post-processing effects |
| `gd-shaders-basics` | Expert Godot shader patterns for batch-safe hitflash, alpha-scissor foliage/dissolve, screenspace postFX, depth reconstruction, triplanar, and instance uniforms — not first-shader tutorials. Trigger on draw-call batching breaks… |
| `gd-signal-architecture` | Expert blueprint for signal-driven architecture using "Signal Up, Call Down" pattern for loose coupling. Covers typed signals, signal chains, one-shot connections, and AutoLoad event buses. Use when implementing event systems O… |
| `gd-state-machine` | Use when implementing state machines in Godot — enum-based, node-based, and resource-based FSM patterns with trade-offs |
| `gd-state-machine-advanced` | Expert blueprint for hierarchical finite state machines (HSM) and pushdown automata for complex AI/character behaviors. Covers state stacks, sub-states, transition validation, and state context passing. Use when basic FSMs are… |
| `gd-testing-patterns` | Expert testing decision trees for GdUnit4: unit vs scene vs CI gates, headless runners, snapshots, and mock networks. Use when choosing test layers, wiring CI, or validating signals/physics without beginner assert catalogs. Key… |
| `gd-theme-easter` | Apply a Classic Easter seasonal overlay: pastel Theme/StyleBox injection, confetti/shimmer VFX, elastic juice, mesh surface_override painting, cursor/audio swaps, and a date-window activation gate with player opt-out. Use when… |
| `gd-tilemap-mastery` | Expert blueprint for TileMapLayer and TileSet systems for efficient 2D level design. Covers terrain autotiling, physics layers, custom data, navigation integration, and runtime manipulation. Use when building grid-based levels… |
| `gd-turn-system` | Expert blueprint for turn-based combat with turn order, action points, phase management, and timeline systems for strategy/RPG games. Covers speed-based initiative, interrupts, and simultaneous turns. Use when implementing turn… |
| `gd-tween-animation` | Use when implementing tweens — property animation, method tweening, chaining, parallel sequences, easing, and common UI/gameplay motion recipes |
| `gd-tweening` | Expert blueprint for programmatic animation using Tween for smooth property transitions, UI effects, camera movements, and juice. Covers easing functions, parallel tweens, chaining, and lifecycle management. Use when implementi… |
| `gd-ui-containers` | Expert blueprint for responsive UI layouts using Container nodes (HBoxContainer, VBoxContainer, GridContainer, MarginContainer, ScrollContainer, HFlowContainer, SubViewportContainer). Covers size flags, anchors, split container… |
| `gd-ui-rich-text` | Expert blueprint for RichTextLabel with BBCode formatting (bold, italic, colors, images, clickable links) and custom effects. Covers meta tags, RichTextEffect shaders, and dynamic content. Use when implementing dialogue systems… |
| `gd-ui-theming` | Expert blueprint for UI themes using Theme resources, StyleBoxes, custom fonts, and theme overrides for consistent visual styling. Covers StyleBoxFlat/Texture, theme inheritance, dynamic theme switching, and font variations. Us… |
| `gd-using-godot-prompter` | Bootstrap skill — establishes how to find and use GodotPrompter skills, with platform-specific tool mapping |
| `gd-version-migration` | Full-history Godot version migration hub. Use when upgrading any Godot project toward the library target (currently 4.7)—from 1.x/2.x legacy eras through 3→4 and hop-by-hop 4.x minors—or finding Domain Skill-scoped migration no… |
| `gd-xr-development` | Use when building VR/AR/XR applications — OpenXR setup, XROrigin3D, hand tracking, controllers, passthrough, and Meta Quest deployment in Godot 4.3+ |
