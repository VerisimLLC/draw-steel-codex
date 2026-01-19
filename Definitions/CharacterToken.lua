--- @class CharacterToken 
--- @field charid string The charid (also known as tokenid) of the token/character. Uniquely identifies this token.
--- @field debugInfo string A summary of this token suitable for outputting to a debug log.
--- @field monitorPath string (Read-only) The 'path' within the game's cloud storage that this token resides at. If you want to see if this token has changed, you can monitor that path. @see Panel.monitorGame
--- @field isCorpse boolean If this token is a corpse
--- @field isObject boolean If this token is an object, not a creature
--- @field isAttackableObject boolean If this token is an attackable object, as opposed to e.g. a corpse.
--- @field objectComponent any 
--- @field hasTokenOnAnyMap boolean If this token is deployed on a map somewhere.
--- @field summonerid nil|string (Read-only) the tokenid of the token that summoned this token, if there is one.
--- @field mountObject nil|LuaObjectComponent The object that this token is mounted on. e.g. sitting on a chair.
--- @field mountedOn nil|string The tokenid of the token this token is mounted on.
--- @field saddleUnlocked boolean If mounted on a saddle, returns true if that saddle is in the 'unlocked' state.
--- @field selfOrMount CharacterToken (Read-only) If mounted on a token, returns the token mounted on. Otherwise is equal to this token itself.
--- @field mount nil|CharacterToken The token we are mounted on, if there is one.
--- @field valid boolean (Read-only) true if this token is still valid. If saving a reference to a CharacterToken between frames, this should be checked before using it. It will become invalid if the token is deleted.
--- @field ModifyProperties @param options {execute: (fun():nil), undoable: nil|boolean, combine: nil|boolean, description: nil|string} This allows you to modify the @see properties of this token and upload it to the cloud. Inside the execute function you supply you should modify the properties of the token. This will observe the changes you make and upload only the diffs. If combine is true the upload will try to occur as a transaction with any other uploads happening this frame. Note that this only uploads the @see properties of the token. It doesn't upload the rest of the token details such as appearance. @see UploadToken to upload the full token.
--- @field uploadable boolean (Read-only) If true, this is a normal CharacterToken that can be uploaded to the cloud service.
--- @field appearanceChangedFromBestiary boolean 
--- @field appearanceVariationIndex number Which appearance variation the token is currently using.
--- @field numAppearanceVariations number The number of appearance variations this token has.
--- @field saddlePositions Vector2[] 
--- @field tokenScale number 
--- @field saddles number 
--- @field saddleSize string 
--- @field saddleSizeNumber number 
--- @field dataPath string Synonym for @see monitorPath
--- @field playerNameOrNil nil|string (Read-only) The name of trhe player controlling this token, or nil if there is none.
--- @field playerName string (Read-only) The name of the player controling this token. Will result in 'NPC Ally' or 'NPC/Monster' if not controlled by a player.
--- @field ownerId nil|string The userid of the player who owns this token, 'PARTY' if the token is owned by a party, nil if the token is GM-controlled. If 'PARTY' then @see partyId to get the partyid of the controlling party.
--- @field partyId nil|string The id of the party that controls this token, if they are controlled by a party.
--- @field playerColor Color (Read-only) the color of the player who owns this token. White if not controlled by a player.
--- @field playerControlled boolean (Read-only) True if this token is controlled by a player, or by the player's party.
--- @field playerControlledNotShared boolean (Read-only) True if this token is controlled directly by a player.
--- @field canControl boolean (Read-only) True if the current user has permissions to control this token (either because they own it, it is in their party, or they are the GM)
--- @field primaryCharacter boolean (Read-only) True if this is the primary character of the current user.
--- @field playerControlledAndPrimary boolean (Read-only) True if this is the primary character of a player.
--- @field activeControllerId nil|string (Read-only) the userid of the user who is best suited to responding to prompts on this token right now. Will return nil if the current user is the best suited to responding to prompts on this character.
--- @field canSee boolean (Read-only) True if the current user can see this token (it's in their vision).
--- @field sheet Panel The panel that is attached to this token to display their UI.
--- @field topsheet Panel The panel that is attached to this token to display their UI.
--- @field bottomsheet Panel The panel that is attached to this token to display their UI.
--- @field canRotate boolean 
--- @field name string 
--- @field namePrivate boolean Whether the name of the token is hidden from players.
--- @field canLocalPlayerSeeName boolean 
--- @field description string 
--- @field squeezed boolean If the token is currently squeezed in a tight spot.
--- @field tileSize number 
--- @field posWithLean Vector2 (Read-only) Where the token should be positioned accounting for how it might be 'leaning' to get line of sight.
--- @field altitudeInDeciTiles integer (Read-only) The altitude of the token in tenths of a tile. This is the altitude above the bottom of the bottom floor on the map.
--- @field altitude integer (Read-only) The altitude of the token in tiles. This is the altitude above the bottom of the bottom floor on the map.
--- @field floorAltitude integer (Read-only) The altitude of the token in tiles. This is relative to the 'zero point' altitude on the current floor.
--- @field characterHeight number (read-only) the number of tiles tall the token is.
--- @field loc Loc (Read-only) The location the token is at.
--- @field locsOccupying Loc[] (Read-only) An array of locations the token is occupying. The number of items in this array will be based on the token's creature size.
--- @field hasConcealment boolean Is true if the token is in a location that has concealment.
--- @field mapid string (Read-only) the id of the map the token is currently on.
--- @field floorid string (Read-only) the id of the floor the token is currently on.
--- @field canCurrentlyClimb boolean True if the creature can climb in the current location it is in now.
--- @field isFriendOfPlayer boolean 
--- @field objectInstance LuaObjectInstance|nil 
--- @field properties Creature The token's lua properties representing game-specific character information. Often this is of type @see Creature
--- @field anthem nil|string 
--- @field anthemVolume number 
--- @field portraitFrameHueShift number 
--- @field portraitFrameSaturation number 
--- @field portraitFrameBrightness number 
--- @field portraitFrame nil|string 
--- @field offTokenPortrait string 
--- @field portrait string 
--- @field popoutPortrait boolean 
--- @field popoutScale number 
--- @field portraitBackground nil|string 
--- @field appearance CharacterAppearance (Read-only) Information about the character's appearance.
--- @field wieldedObjectsOverride nil|{mainhand: nil|string, offhand: nil|string, belt: nil|string} 
--- @field despawned boolean 
--- @field invisibleToPlayers boolean 
--- @field portraitRect Vector4 The rectangle within the portrait to display for this token.
--- @field radiusInTiles number The radius of the token, in tiles.
--- @field pos Vector2 (Read-only) The world position the token is at.
--- @field posWithParallax Vector2 (Read-only) The world position the token is at, including adjustments due to parallax.
--- @field portraitZoom number 
--- @field portraitOffset Vector2 
--- @field creatureSize string (Read-only) the size of the creature.
--- @field creatureSizeNumber number (Read-only) the creature size as a 1-based number.
--- @field creatureDimensions Vector2 (Read-only) The width/height of the token.
--- @field chargeDistance number 
--- @field lookAtMouse boolean 
--- @field floorIndex number 
--- @field initiativeStatus InitiativeStatus (Read-only) the initiative status of the token.
CharacterToken = {}

--- IsPreviewToken: Returns true if this token id is not a 'real' in game token but instead a preview token shown to an in app camera.
--- @param id string
--- @return boolean
function CharacterToken.IsPreviewToken(id)
	-- dummy implementation for documentation purposes only
end

--- FindCorpse: Finds the corpse object for this creature
--- @return any
function CharacterToken:FindCorpse()
	-- dummy implementation for documentation purposes only
end

--- BeginChanges: (Deprecated): @see ModifyProperties instead.
--- @param reentrant any
--- @return nil
function CharacterToken:BeginChanges(reentrant)
	-- dummy implementation for documentation purposes only
end

--- CompleteChanges: (Deprecated): @see ModifyProperties instead.
--- @param description string
--- @param options any
--- @return nil
function CharacterToken:CompleteChanges(description, options)
	-- dummy implementation for documentation purposes only
end

--- UploadToken: Upload any changes to the token to the cloud. Note that if you are only modifying @see properties you should use @see ModifyProperties instead.
--- @param description string
--- @return nil
function CharacterToken:UploadToken(description)
	-- dummy implementation for documentation purposes only
end

--- RefreshAppearanceLocally: Refresh the appearance if it has changed. This should happen automatically so only use for debugging purposes if a token isn't updating the way you expect.
--- @return nil
function CharacterToken:RefreshAppearanceLocally()
	-- dummy implementation for documentation purposes only
end

--- SerializeAppearanceToString
--- @return string
function CharacterToken:SerializeAppearanceToString()
	-- dummy implementation for documentation purposes only
end

--- SerializeAppearanceFromString
--- @param s string
--- @return nil
function CharacterToken:SerializeAppearanceFromString(s)
	-- dummy implementation for documentation purposes only
end

--- UploadAppearance: Upload the @see appearance section of the token.
--- @return nil
function CharacterToken:UploadAppearance()
	-- dummy implementation for documentation purposes only
end

--- DisguiseAs: Disguise as another token. The disguise will be uploaded.
--- @param otherToken any
--- @return nil
function CharacterToken:DisguiseAs(otherToken)
	-- dummy implementation for documentation purposes only
end

--- SwitchAppearanceVariation
--- @param nindex number
--- @return nil
function CharacterToken:SwitchAppearanceVariation(nindex)
	-- dummy implementation for documentation purposes only
end

--- DeleteAppearanceVariation
--- @param index number
--- @return nil
function CharacterToken:DeleteAppearanceVariation(index)
	-- dummy implementation for documentation purposes only
end

--- GetVariationInfo
--- @param index integer The index of the appearance variation to query.
--- @return {portrait: string, portraitFrame: string, portraitFrameHueShift: number, portraitFrameSaturation: number, portraitFrameBrightness: number, portraitBackground: nil|string, anthem: nil|string, anthemVolume: number}
function CharacterToken:GetVariationInfo(index)
	-- dummy implementation for documentation purposes only
end

--- UpdateAuras
--- @return nil
function CharacterToken:UpdateAuras()
	-- dummy implementation for documentation purposes only
end

--- RecalculateElevation: Recalculate the token's elevation based on map changes.
--- @return nil
function CharacterToken:RecalculateElevation()
	-- dummy implementation for documentation purposes only
end

--- Flip: Flip the direction the token is facing horizontally.
--- @return nil
function CharacterToken:Flip()
	-- dummy implementation for documentation purposes only
end

--- GetNameMaxLength
--- @param maxLen number
--- @return string
function CharacterToken:GetNameMaxLength(maxLen)
	-- dummy implementation for documentation purposes only
end

--- DescribeRollAgainst
--- @param rollStr string
--- @return string
function CharacterToken:DescribeRollAgainst(rollStr)
	-- dummy implementation for documentation purposes only
end

--- PosAtLoc: Where the token should be positioned if it's standing at the given location.
--- @param loc Loc
--- @return Vector3
function CharacterToken:PosAtLoc(loc)
	-- dummy implementation for documentation purposes only
end

--- ExecuteWithTheoreticalLoc: Given a location and a function will execute the function with the token at that location.
--- @param loc Loc The hypothetical location to execute the function from.
--- @param fn function The function to execute.
function CharacterToken:ExecuteWithTheoreticalLoc(loc, fn)
	-- dummy implementation for documentation purposes only
end

--- GetLocsWithinRadius
--- @param radius number The radius to search
--- @return Loc[] A list of locs within the radius of this token. This includes the locs the token occupies
function CharacterToken:GetLocsWithinRadius(radius)
	-- dummy implementation for documentation purposes only
end

--- LocsOccupyingWhenAt: The locations this token would occupy if it was at the given location.
--- @param loc Loc
--- @return Loc[]
function CharacterToken:LocsOccupyingWhenAt(loc)
	-- dummy implementation for documentation purposes only
end

--- GetFallInfoFromLoc: Given a location this token wants to move to, returns nil if the token wouldn't fall when moving there, otherwise returns information about the fall.
--- @param location Loc
--- @return nil|{floorIndex: number, label: string, loc: Loc}
function CharacterToken:GetFallInfoFromLoc(location)
	-- dummy implementation for documentation purposes only
end

--- BeginDragMovement: Begin dragging this token.
--- @param args any
--- @return nil
function CharacterToken:BeginDragMovement(args)
	-- dummy implementation for documentation purposes only
end

--- MoveVertical: Move the token vertically to the new altitude.
--- @param newAltitude number
--- @return nil
function CharacterToken:MoveVertical(newAltitude)
	-- dummy implementation for documentation purposes only
end

--- TryFall: Make the character fall if they are in mid air.
--- @return nil
function CharacterToken:TryFall()
	-- dummy implementation for documentation purposes only
end

--- Move
--- @param loc Loc The location to move to.
--- @param options {maxCost: nil|number, straightline: nil|boolean, ignorecreatures = nil|boolean, moveThroughFriends: nil|boolean, ignoreFalling: nil|boolean, movementType: nil|MovementType}
--- @return nil|LuaPath
function CharacterToken:Move(loc, options)
	-- dummy implementation for documentation purposes only
end

--- Teleport: Teleport the token to the target location.
--- @param loc Loc
--- @param teleportMount boolean Teleport the mount also if this creature is mounted.
function CharacterToken:Teleport(loc, teleportMount)
	-- dummy implementation for documentation purposes only
end

--- ChangeLocation: Immediately relocate creature to target location
--- @param loc Loc
function CharacterToken:ChangeLocation(loc)
	-- dummy implementation for documentation purposes only
end

--- SwapPositions: Make the token swap positions with the target token.
--- @param targetToken CharacterToken
function CharacterToken:SwapPositions(targetToken)
	-- dummy implementation for documentation purposes only
end

--- IsFriend
--- @param other CharacterToken
--- @return boolean
function CharacterToken:IsFriend(other)
	-- dummy implementation for documentation purposes only
end

--- InvalidateObjects: Refresh any objects attached to the token.
--- @return nil
function CharacterToken:InvalidateObjects()
	-- dummy implementation for documentation purposes only
end

--- GetPortraitRectForAspect: aspect is the width as a percentage of the height. e.g. 0.5 = width is half of height.
--- @param aspect float
--- @return Vector4
function CharacterToken:GetPortraitRectForAspect(aspect, portraitLua)
	-- dummy implementation for documentation purposes only
end

--- GetGroundMoveType: Returns walk of swim depending on the type of movement the creature will have to move on the ground. preferWater is used if the token straddles water and land and chooses the preferred type for the token.
--- @param preferWater boolean
--- @return 'walk'|'swim'
function CharacterToken:GetGroundMoveType(preferWater)
	-- dummy implementation for documentation purposes only
end

--- ShowSheet: Reveals the token's character sheet, going to the given tab by default
--- @param tabid string
--- @return nil
function CharacterToken:ShowSheet(tabid)
	-- dummy implementation for documentation purposes only
end

--- GetLineOfSight: The vision of the other token you have. 1 = full vision. 0 = complete occlusion. 0.5 = half visible.
--- @param otherToken any
--- @return number
function CharacterToken:GetLineOfSight(otherToken)
	-- dummy implementation for documentation purposes only
end

--- Distance: The distance in native units to a loc, path, or another token.
--- @param otherTokenOrLoc CharacterToken|LuaPath|Loc
--- @result number
function CharacterToken:Distance(otherTokenOrLoc)
	-- dummy implementation for documentation purposes only
end

--- GetNearbyTokens
--- @param radius number Radius in native units (default=one tile)
--- @return CharacterToken[]
function CharacterToken:GetNearbyTokens(radiusLua)
	-- dummy implementation for documentation purposes only
end

--- GetAurasTouching
--- @return Aura[]
function CharacterToken:GetAurasTouching()
	-- dummy implementation for documentation purposes only
end

--- ForcedPush
--- @param pushingToken any
--- @param distanceInFeet number
--- @return nil
function CharacterToken:ForcedPush(pushingToken, distanceInFeet)
	-- dummy implementation for documentation purposes only
end

--- RunFunctionAtLoc
--- @param lualoc any
--- @param fn any
--- @return any
function CharacterToken:RunFunctionAtLoc(lualoc, fn)
	-- dummy implementation for documentation purposes only
end

--- CalculatePathfindingArea
--- @param movementAllowanceDecis
--- @return table<{x: number, y: number}, {loc: Loc, cost: number}>
function CharacterToken:CalculatePathfindingArea(movementAllowanceDecis, luaFlags)
	-- dummy implementation for documentation purposes only
end

--- AnimateAttack
--- @param options {targetid: string, rollid: string, damage: integer, outcome: AttackAnimOutcome}
function CharacterToken:AnimateAttack(options)
	-- dummy implementation for documentation purposes only
end

--- ConsumeClick
--- @return nil
function CharacterToken:ConsumeClick()
	-- dummy implementation for documentation purposes only
end

--- Render: Renders this token's creature into a tooltip panel and returns it.
--- @param args table
--- @param options table
--- @result nil|Panel
function CharacterToken:Render(args, options)
	-- dummy implementation for documentation purposes only
end

--- MarkMovementRadius: Renders a movement radius marker showing how far the token can move. Returns a reference controlling it. Remember to call Destroy on it when you want the radius to disappear!
--- @param movementAllowance movement allowance in decitiles.
--- @param args nil|{waypoints: nil|Loc[], mask: nil|Loc[], filter: nil|function, moveFlags: nil|('IgnoreMovementType'|'CannotMoveThroughFriends'|'CanFly'|'IgnoreOtherCreatures'|'Shifting')[] }
--- @return LuaMultiObjectReference
function CharacterToken:MarkMovementRadius(movementAllowance, args)
	-- dummy implementation for documentation purposes only
end

--- MarkMovementArrow: Draw a movement arrow. @see ClearMovementArrow to clear the movement arrow.
--- @param targetLoc Loc
--- @param options nil|table
--- @return nil|{path: LuaPath, collideWith: CharacterToken[]}
function CharacterToken:MarkMovementArrow(targetLoc, options)
	-- dummy implementation for documentation purposes only
end

--- ClearMovementArrow
--- @return nil
function CharacterToken:ClearMovementArrow()
	-- dummy implementation for documentation purposes only
end
