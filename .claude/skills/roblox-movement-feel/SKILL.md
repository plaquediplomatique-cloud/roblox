---
name: roblox-movement-feel
description: Movement and camera game feel for Roblox — acceleration and deceleration curves, sprint, jump buffering and coyote time, air control, landing impact, turning, camera smoothing with springs, FOV kicks, head bob tied to distance travelled, separating juice from aim, animation blending and stride matching, plus the feel of interactive objects (doors, sliding doors, elevators, moving platforms, vehicles). Use whenever the user says movement feels rigid, floaty, amateur or unresponsive, or asks about marche, course, sprint, saut, chute, atterrissage, accélération, head bob, caméra, transitions d'animation, portes, ascenseurs, véhicules, even if they only say "make the controls feel better".
---

# Roblox Movement and Camera Feel

Good movement is **responsive at the input, smooth in the output, and honest in the
camera**: the character reacts within one frame, speed changes follow curves instead of steps,
and every camera effect is layered on top of the real aim without changing it.

**Boundaries.** Camera API and CFrame math → `roblox-camera`. Input binding → `roblox-input`.
Animation playback, VFX and tweens → `roblox-animation-vfx`. Physics assemblies, constraints,
vehicles → `roblox-physics`. This skill gives the *feel targets and recipes*.

## 1. Feel targets (measure them)

| Quantity | Snappy shooter | Third-person action | Exploration / cosy |
|---|---|---|---|
| Time to full speed | 0.12–0.2 s | 0.2–0.35 s | 0.3–0.5 s |
| Stop time from full speed | 0.05–0.14 s | 0.15–0.25 s | 0.25–0.4 s |
| Sprint speed vs walk | 1.3–1.5× | 1.4–1.7× | 1.3× |
| Jump buffer / coyote time | 0.1–0.15 s / 0.08–0.12 s | same | same |
| FOV kick on sprint | +4–8° | +6–10° | +3–5° |
| Head-bob amplitude | 0–0.06 stud (setting) | 0.04–0.1 | 0.05–0.12 |

Record speed over time while pressing and releasing a direction (print the HRP's horizontal
velocity each frame) and compare with the targets instead of judging by feel alone.

## 2. Controller options

- **Humanoid + custom curves** (most games): keep `Humanoid` for collisions and steps, drive
  speed yourself. This repository's `src/Client/Controllers/MovementController.luau` is a
  complete reference: Source-style friction + acceleration from the real velocity, counter-
  strafing, jump buffer and coyote time, air-speed cap, slide, lean, landing slow-down.
- **ControllerManager** (engine character controller): `GroundController.AccelerationTime`,
  `DecelerationTime`, `TurnSpeedFactor`, `Friction`; `AirController` for air control. Tune
  these instead of writing curves when you build a physics-based character.
- **Plain Humanoid defaults** reach full speed almost instantly and stop dead: fine for
  obbies, rigid for action games.

## 3. Recipes

**Acceleration without a custom controller** — ramp `WalkSpeed` toward the target with
exponential smoothing (frame-rate independent), and give sprint its own camera response:

```lua
--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local WALK, SPRINT = 16, 24
local ACCEL, DECEL = 10, 16 -- 1/s: higher = snappier
local FOV_BASE, FOV_SPRINT = 70, 77

local player = Players.LocalPlayer
local speed, fov, bobPhase = 0, FOV_BASE, 0

RunService.RenderStepped:Connect(function(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if not (character and humanoid and camera) then
		return
	end
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local sprinting = moving and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
	local target = if moving then (if sprinting then SPRINT else WALK) else 0
	local rate = if target > speed then ACCEL else DECEL
	speed += (target - speed) * (1 - math.exp(-rate * dt))
	humanoid.WalkSpeed = math.max(speed, 0.01)

	fov += ((if sprinting then FOV_SPRINT else FOV_BASE) - fov) * (1 - math.exp(-8 * dt))
	camera.FieldOfView = fov

	-- Head bob tied to distance travelled, not to time: steps match the stride.
	local root = character:FindFirstChild("HumanoidRootPart")
	local velocity = if root and root:IsA("BasePart") then root.AssemblyLinearVelocity else Vector3.zero
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	bobPhase += horizontal * dt / 2.6 * math.pi
	local amount = math.clamp(horizontal / SPRINT, 0, 1) * 0.08
	humanoid.CameraOffset = Vector3.new(math.cos(bobPhase * 0.5) * amount, math.abs(math.sin(bobPhase)) * amount, 0)
end)
```

**Jump buffer and coyote time:** store the time of the last jump press and the last grounded
time (`Humanoid.FloorMaterial ~= Enum.Material.Air`); jump when both are within their windows.

**Landing:** scale a camera dip and a short speed penalty with fall speed; play a landing sound
whose volume follows the impact (see `roblox-sound-design`).

**Turning:** for third person, rotate the body toward movement with damping (12–16 /s);
for shooters, align the body to the camera yaw (this repo uses `AlignOrientation`).

## 4. Camera layering

Compose the camera as **aim (yaw/pitch, what bullets follow) → render offsets (bob, punch,
shake, roll, FOV kick)**. Effects never feed back into aim. Use critically damped springs for
FOV, punch and smoothing so the result is identical at 30 and 240 FPS
(`src/Shared/Util/Spring.luau` is an analytic implementation; `CameraController.luau` shows the
full layering). Shake = trauma² × noise, decaying; never random jitter per frame.

## 5. Animation blending

- Fade between tracks over 0.1–0.25 s (`Play(fadeTime)`, `Stop(fadeTime)`); instant switches
  read as pops.
- Blend walk/run by speed with `AdjustWeight` on both tracks, and keep feet planted with
  `AdjustSpeed(currentSpeed / authoredSpeed)` (stride matching).
- Priorities: `Core` < `Idle` < `Movement` < `Action` (`Action2–4` above); upper-body actions
  (reload, wave) on `Action` with only upper-body keys.
- Footstep sounds from animation markers (`GetMarkerReachedSignal`) or from distance
  travelled — both beat timers.
- Procedural layers (lean, look-at, recoil, breathing) on top of authored clips keep motion
  alive; this repository animates its third-person characters procedurally in
  `src/Client/Controllers/CharacterAnimator.luau`.

## 6. Interactive objects

- **Hinged doors:** server owns the state (open/closed, locked), clients animate. Tween the
  door's pivot on clients over 0.35–0.6 s with `Quad`/`Back` out; play open/close sounds at
  the hinge; collision follows the server state.
- **Sliding doors / elevators / moving platforms:** players are only carried by physically
  simulated assemblies. Use a `PrismaticConstraint` (`ActuatorType = Servo`, `TargetPosition`,
  `Speed`, `ServoMaxForce`) on an unanchored platform with server network ownership instead of
  tweening an anchored part's CFrame (riders slide off a tweened anchored part).
- **Vehicles:** acceleration and steering through curves, not instant values; camera follow
  with lag and a speed-based FOV; suspension via `SpringConstraint` (see `roblox-physics`).

## 7. Review checklist

- [ ] Input to visible reaction within one frame; no input lost during transitions.
- [ ] Measured accel/stop times match the target column.
- [ ] Jump buffer and coyote time present; landings have weight but do not stall control.
- [ ] Camera effects never change where bullets or interactions go.
- [ ] Animations fade; feet do not slide at any speed.
- [ ] Doors/elevators: server-owned state, client visuals, riders carried correctly.
