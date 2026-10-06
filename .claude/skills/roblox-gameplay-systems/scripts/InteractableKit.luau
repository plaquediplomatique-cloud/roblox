--!strict
--[[
	InteractableKit — server-authoritative interactable objects (doors, switches, lockers,
	terminals, pickups) on ProximityPrompt, with client-side visuals driven by a replicated
	"State" attribute.

	Server (one call per kind of object):
		InteractableKit.register({
			tag = "Door",
			states = { "Closed", "Open" },
			initial = "Closed",
			objectText = "Door",
			actionText = function(state) return if state == "Open" then "Close" else "Open" end,
			cooldown = 0.6,
			transition = function(context)
				return if context.state == "Open" then "Closed" else "Open"
			end,
			onChanged = function(model, state) -- collision and queries follow the server state
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") and (part.Name == "Leaf" or part.Name == "Handle") then
						part.CanCollide = part.Name == "Leaf" and state == "Closed"
						part.CanQuery = state == "Closed"
					end
				end
			end,
		})

	Client (visual only, every client animates locally and late joiners snap to the state):
		InteractableKit.bindVisual("Door", InteractableKit.hingeVisual({
			parts = { "Leaf", "Handle" }, openStates = { "Open" }, angle = 100, duration = 0.45,
		}))

	Models are found by CollectionService tag. The prompt goes on the model's child named
	"PromptAnchor" (Attachment or BasePart), else its PrimaryPart, else its first BasePart.
	Every use is re-validated on the server (alive, distance with latency margin, cooldown,
	custom `canUse`, known target state): the prompt is a UI, not an authority.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

export type Context = {
	player: Player,
	model: Model,
	state: string,
	distance: number,
}

export type Definition = {
	tag: string,
	states: { string },
	initial: string,
	actionText: (state: string) -> string,
	objectText: string?,
	holdDuration: number?,
	maxDistance: number?,
	cooldown: number?,
	canUse: ((context: Context) -> (boolean, string?))?,
	transition: (context: Context) -> string?,
	onChanged: ((model: Model, state: string, previous: string, player: Player?) -> ())?,
}

export type Decision = { ok: boolean, reason: string?, nextState: string? }

export type Visual = (model: Model, state: string, previous: string?, instant: boolean) -> ()

export type HingeOptions = {
	parts: { string }, -- names of the parts that swing together (leaf, handles…)
	openStates: { string },
	angle: number?, -- degrees; positive swings toward -Z (the front, PropKit convention), negative inward
	duration: number?,
	hingeSide: ("Left" | "Right")?, -- default: the leaf's "HingeSide" attribute, else Left
	leafName: string?, -- part that defines the hinge edge (default "Leaf")
}

local InteractableKit = {}

local DISTANCE_MARGIN = 4 -- studs of latency tolerance on top of the prompt distance

-- Pure validation step: decides whether a use is accepted and which state follows.
function InteractableKit.decide(definition: Definition, context: Context, now: number, lastUse: number?): Decision
	if context.distance > (definition.maxDistance or 8) + DISTANCE_MARGIN then
		return { ok = false, reason = "TooFar" }
	end
	if lastUse and now - lastUse < (definition.cooldown or 0.5) then
		return { ok = false, reason = "Cooldown" }
	end
	local canUse = definition.canUse
	if canUse then
		local allowed, reason = canUse(context)
		if not allowed then
			return { ok = false, reason = reason or "Denied" }
		end
	end
	local nextState = definition.transition(context)
	if nextState ~= nil and not table.find(definition.states, nextState) then
		return { ok = false, reason = "UnknownState" }
	end
	return { ok = true, nextState = nextState }
end

-- Pure hinge math: where a part sits when its door is rotated by `angle` radians about the
-- vertical axis through `hinge`.
function InteractableKit.hingeCFrame(closed: CFrame, hinge: CFrame, angle: number): CFrame
	return hinge * CFrame.Angles(0, angle, 0) * hinge:Inverse() * closed
end

local function anchorOf(model: Model): Instance?
	local anchor = model:FindFirstChild("PromptAnchor")
	if anchor and (anchor:IsA("Attachment") or anchor:IsA("BasePart")) then
		return anchor
	end
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function positionOf(anchor: Instance): Vector3
	if anchor:IsA("Attachment") then
		return anchor.WorldPosition
	end
	return (anchor :: BasePart).CFrame.Position
end

local function stateOf(model: Model, definition: Definition): string
	local state = model:GetAttribute("State")
	return if typeof(state) == "string" then state else definition.initial
end

-- Server: makes every model tagged `definition.tag` interactable. Returns a cleanup function.
function InteractableKit.register(definition: Definition): () -> ()
	assert(RunService:IsServer(), "InteractableKit.register runs on the server")
	local perModel: { [Model]: { RBXScriptConnection } } = {}
	local lastUse: { [Model]: number } = {}

	local function release(instance: Instance)
		if not instance:IsA("Model") then
			return
		end
		local list: { RBXScriptConnection } = perModel[instance] or {}
		for _, connection in list do
			connection:Disconnect()
		end
		perModel[instance] = nil
		lastUse[instance] = nil
		local anchor = anchorOf(instance)
		local prompt = anchor and anchor:FindFirstChild("InteractPrompt")
		if prompt then
			prompt:Destroy()
		end
	end

	local function setup(instance: Instance)
		if not instance:IsA("Model") or perModel[instance] then
			return
		end
		local model = instance
		local anchor = anchorOf(model)
		if not anchor then
			warn(("InteractableKit: %s has no PromptAnchor or BasePart"):format(model:GetFullName()))
			return
		end
		local initial = stateOf(model, definition)
		model:SetAttribute("State", initial)

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "InteractPrompt"
		prompt.ObjectText = definition.objectText or ""
		prompt.ActionText = definition.actionText(initial)
		prompt.HoldDuration = definition.holdDuration or 0
		prompt.MaxActivationDistance = definition.maxDistance or 8
		prompt.RequiresLineOfSight = true
		prompt.Parent = anchor

		perModel[model] = {
			prompt.Triggered:Connect(function(player: Player)
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if not (humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
					return
				end
				local current = stateOf(model, definition)
				local context: Context = {
					player = player,
					model = model,
					state = current,
					distance = (root.CFrame.Position - positionOf(anchor)).Magnitude,
				}
				local now = os.clock()
				local decision = InteractableKit.decide(definition, context, now, lastUse[model])
				if not decision.ok then
					return
				end
				lastUse[model] = now
				local nextState = decision.nextState
				if nextState and nextState ~= current then
					model:SetAttribute("State", nextState)
					prompt.ActionText = definition.actionText(nextState)
					local onChanged = definition.onChanged
					if onChanged then
						onChanged(model, nextState, current, player)
					end
				end
			end),
		}
		local onChanged = definition.onChanged
		if onChanged then
			onChanged(model, initial, initial, nil)
		end
	end

	local connections = {
		CollectionService:GetInstanceAddedSignal(definition.tag):Connect(setup),
		CollectionService:GetInstanceRemovedSignal(definition.tag):Connect(release),
	}
	for _, instance in CollectionService:GetTagged(definition.tag) do
		setup(instance)
	end
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		for model in perModel do
			release(model)
		end
	end
end

-- Client: runs `visual` for every tagged model now (instant) and on each state change.
-- Handles streaming: models that stream out are released and re-bound when they return.
function InteractableKit.bindVisual(tag: string, visual: Visual): () -> ()
	local perModel: { [Model]: RBXScriptConnection } = {}

	local function watch(instance: Instance)
		if not instance:IsA("Model") or perModel[instance] then
			return
		end
		local model = instance
		local previous: string? = nil
		local function apply(instant: boolean)
			local state = model:GetAttribute("State")
			if typeof(state) == "string" and state ~= previous then
				visual(model, state, previous, instant)
				previous = state
			end
		end
		perModel[model] = model:GetAttributeChangedSignal("State"):Connect(function()
			apply(false)
		end)
		apply(true)
	end

	local function unwatch(instance: Instance)
		if instance:IsA("Model") and perModel[instance] then
			perModel[instance]:Disconnect()
			perModel[instance] = nil
		end
	end

	local connections = {
		CollectionService:GetInstanceAddedSignal(tag):Connect(watch),
		CollectionService:GetInstanceRemovedSignal(tag):Connect(unwatch),
	}
	for _, instance in CollectionService:GetTagged(tag) do
		watch(instance)
	end
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		for model in perModel do
			unwatch(model)
		end
	end
end

-- Ready-made client visual: swings the named parts about the leaf's hinge edge.
function InteractableKit.hingeVisual(options: HingeOptions): Visual
	local closedPose: { [Model]: { [BasePart]: CFrame } } = setmetatable({}, { __mode = "k" }) :: any
	local hinges: { [Model]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
	local signs: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
	local drivers: { [Model]: NumberValue } = setmetatable({}, { __mode = "k" }) :: any
	local tweens: { [Model]: Tween } = setmetatable({}, { __mode = "k" }) :: any
	local angle = math.rad(options.angle or 100)
	local duration = options.duration or 0.45

	local function capture(model: Model): boolean
		if closedPose[model] then
			return true
		end
		local leaf = model:FindFirstChild(options.leafName or "Leaf", true)
		if not (leaf and leaf:IsA("BasePart")) then
			return false
		end
		local side = options.hingeSide or leaf:GetAttribute("HingeSide")
		local sign = if side == "Right" then 1 else -1
		hinges[model] = leaf.CFrame * CFrame.new(sign * leaf.Size.X / 2, 0, 0)
		signs[model] = -sign -- a left hinge opens with a positive yaw, a right hinge negative
		local pose: { [BasePart]: CFrame } = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") and table.find(options.parts, descendant.Name) then
				pose[descendant] = descendant.CFrame
			end
		end
		closedPose[model] = pose
		return true
	end

	local function poseAt(model: Model, alpha: number)
		local hinge = hinges[model]
		local yaw = alpha * angle * signs[model]
		for part, closed in closedPose[model] do
			part.CFrame = InteractableKit.hingeCFrame(closed, hinge, yaw)
		end
	end

	-- Tween driver created on first animated change (instant changes never need one).
	local function driver(model: Model, from: number): NumberValue
		local existing = drivers[model]
		if existing then
			return existing
		end
		local value = Instance.new("NumberValue")
		value.Value = from
		value.Changed:Connect(function(alpha: number)
			poseAt(model, alpha)
		end)
		drivers[model] = value
		return value
	end

	return function(model: Model, state: string, previous: string?, instant: boolean)
		if not capture(model) then
			return
		end
		local target = if table.find(options.openStates, state) then 1 else 0
		local running = tweens[model]
		if running then
			running:Cancel()
			tweens[model] = nil
		end
		local existing = drivers[model]
		if instant then
			if existing then
				existing.Value = target
			else
				poseAt(model, target)
			end
			return
		end
		local from = if previous and table.find(options.openStates, previous) then 1 else 0
		local value = driver(model, from)
		local tween = TweenService:Create(
			value,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Value = target }
		)
		tweens[model] = tween
		tween:Play()
	end
end

return InteractableKit
