SWEP.PrintName = "Empty Hand"

SWEP.Slot = 0
SWEP.SlotPos = 0

SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = ""

SWEP.DrawAmmo = false

SWEP.Primary.Ammo = "none"
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1

SWEP.Secondary = SWEP.Primary

SWEP.VRInfo = { mainHand = VR_HAND_NONE, inHands = VR_HAND_NONE }

function SWEP:Initialize()
	self:SetHoldType( "normal" )
end

function SWEP:PrimaryAttack() end
function SWEP:SecondaryAttack() end
function SWEP:Reload() end