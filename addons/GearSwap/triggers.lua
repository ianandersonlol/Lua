--Copyright (c) 2013, Byrthnoth
--All rights reserved.

--Redistribution and use in source and binary forms, with or without
--modification, are permitted provided that the following conditions are met:

--    * Redistributions of source code must retain the above copyright
--      notice, this list of conditions and the following disclaimer.
--    * Redistributions in binary form must reproduce the above copyright
--      notice, this list of conditions and the following disclaimer in the
--      documentation and/or other materials provided with the distribution.
--    * Neither the name of <addon name> nor the
--      names of its contributors may be used to endorse or promote products
--      derived from this software without specific prior written permission.

--THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
--ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
--WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
--DISCLAIMED. IN NO EVENT SHALL <your name> BE LIABLE FOR ANY
--DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
--(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
--LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
--ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
--(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
--SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.




-----------------------------------------------------------------------------------
--Name: outgoing_text(original,modified)
--Desc: Searches the client's outgoing text for GearSwap handled commands and 
--      returns '' if it finds one. Otherwise returns the command unaltered.
--Args:
---- original - String entered by the user
---- modified - String after being modified by upstream addons/plugins
-----------------------------------------------------------------------------------
--Returns:
---- none or ''
-----------------------------------------------------------------------------------
windower.register_event('outgoing text',function(original,modified)
	if debugging >= 1 then windower.debug('outgoing text (debugging)') end
	if gearswap_disabled then return modified end
	
	local temp_mod = windower.convert_auto_trans(modified):gsub(' <wait %d+>','')
	local splitline = temp_mod:split(' ')
	local command = splitline[1]
	
	local a,b,abil = string.find(temp_mod,'"(.-)"')
	if abil then
		abil = abil:lower()
	elseif splitline.n == 3 then
		abil = splitline[2]:lower()
	end
	
	local temptarg,temp_mob_arr = valid_target(splitline[splitline.n])
	if command_list[command] and temptarg and (validabils[language][unify_prefix[command]][abil] or unify_prefix[command]=='/ra') then
		if st_flag then
			st_flag = nil
			return true
		elseif temp_mob_arr then
			if logging then	logit(logfile,'\n\n'..tostring(os.clock)..'(93) temp_mod: '..temp_mod) end
			if clocking then out_time = os.clock() end
			refresh_globals()
	
			local r_line
				
			if command_list[command] == 'Magic' then
				r_line = r_spells[validabils[language][unify_prefix[command]][abil]]
				storedcommand = command..' "'..r_line[language]..'" '
			elseif command_list[command] == 'Ability' then
				r_line = r_abilities[validabils[language][unify_prefix[command]][abil]]
				storedcommand = command..' "'..r_line[language]..'" '
			elseif command_list[command] == 'Item' then
				r_line = r_items[validabils[language][unify_prefix[command]][abil]]
				r_line.prefix = '/item'
				r_line.type = 'Item'
				storedcommand = command..' "'..r_line[language]..'" '
			elseif command_list[command] == 'Ranged Attack' then
				r_line = r_abilities[1]
				storedcommand = command..' '
			end
			
			r_line.name = r_line[language]
			spell = aftercast_cost(r_line)
			spell.target = temp_mob_arr
			spell.action_type = command_list[command]
			
			if tonumber(splitline[splitline.n]) then
				local ts,id = find_command_registry_key('command',unify_prefix[spell.prefix]..' "'..spell.english..'" nil') or mk_command_registry_entry(spell,spell.target.id)
				
				if outgoing_action_category_table[unify_prefix[spell.prefix]] == 3 then
					id = spell.index
				else
					id = spell.id
				end
				command_registry[ts].proposed_packet = assemble_action_packet(spell.target.id,spell.target.index,outgoing_action_category_table[unify_prefix[spell.prefix]],id)
				if command_registry[ts].proposed_packet then
					equip_sets('precast',ts,spell)
					return true
				end
			else
				return equip_sets('pretarget',os.time(),spell)
			end
		end
	end
	return modified
end)



-----------------------------------------------------------------------------------
--Name: inc_action(act)
--Desc: Calls midcast or aftercast functions as appropriate in response to incoming
--      action packets.
--Args:
---- act - Action packet array (described on the dev wiki)
-----------------------------------------------------------------------------------
--Returns:
---- none
-----------------------------------------------------------------------------------
function inc_action(act)
	if debugging >= 1 then windower.debug('action') end
	if gearswap_disabled or act.category == 1 then return end
	
	local temp_player = windower.ffxi.get_player()
	local temp_player_mob_table = windower.ffxi.get_mob_by_index(temp_player.index)
	local player_id = temp_player.id
	-- Update player info for aftercast costs.
	player.tp = temp_player.vitals.tp
	player.mp = temp_player.vitals.mp
	player.mpp = temp_player.vitals.mpp
	
	local temp_pet,pet_id
	if temp_player_mob_table.pet_index then
		temp_pet = windower.ffxi.get_mob_by_index(temp_player_mob_table.pet_index)
		if temp_pet then
			pet_id = temp_pet.id
		end
	end

	if act.actor_id ~= player_id and act.actor_id ~= pet_id then
		return -- If the action is not being used by the player, the pet, or is a melee attack then abort processing.
	end
	
	local prefix = ''
	
	if act.actor_id == pet_id then 
		prefix = 'pet_'
	end
	
	spell = get_spell(act)
	local category = act.category
	if logging then	
		if spell then logit(logfile,'\n\n'..tostring(os.clock)..'(178) Event Action: '..tostring(spell.english)..' '..tostring(act.category))
		else logit(logfile,'\n\nNil spell detected') end
	end
	
	local inde
	if spell and spell.english then
		local pre = get_prefix(spell.prefix)
		inde = pre..' "'..spell.english..'"'
		spell.target = target_complete(windower.ffxi.get_mob_by_id(act.targets[1].id))
		spell.action_type = command_list[pre]
	else
		if debugging >= 1 then windower.add_to_chat(123,'Incoming Action packet did not generate a spell. '..tostring((spell or {})['prefix'])) end
		return
	end
	
	-- Paralysis of JAs/spells/etc. and Out of Range messages for avatars both send two action packets when they occur.
	-- The first packet is a paralysis packet that contains the message and spell-appropriate information.
	-- The second packet contains the interruption code and no useful information as far as I can see.
	-- The same occurs for items, except that they are both category 9 messages.
	
	-- For some reason avatar Out of Range messages send two packets (Category 4 and Category 7)
	-- Category 4 contains real information, while Category 7 does not.
	-- I do not know if this will affect automatons being interrupted.
	
	ts = find_command_registry_key('spell',spell)

	if (jas[act.category] or uses[act.category]) then
		if uses[act.category] and act.param == 28787 then
			spell.action_type = 'Interruption'
			spell.interrupted = true
		end
		if ts then
			-- Only aftercast things that were precasted.
			-- Also, there are some actions (like being paralyzed while casting Ninjutsu) that sends two result action packets. Block the second packet.
			refresh_globals()
			equip_sets(prefix..'aftercast',ts,spell)
		elseif debugging >= 1 then
			windower.add_to_chat(8,'GearSwap (Debug Mode): Hitting Aftercast without detecting an entry in command_registry')
		end
	elseif (readies[act.category] and act.param == 28787) then -- and not (act.category == 9 or (act.category == 7 and prefix == 'pet_'))) then
		spell.action_type = 'Interruption'
		spell.interrupted = true
		if ts then
			-- Only aftercast things that were precasted.
			-- Also, there are some actions (like being paralyzed while casting Ninjutsu) that sends two result action packets. Block the second packet.
			refresh_globals()
			equip_sets(prefix..'aftercast',ts,spell)
		elseif debugging >= 1 then
			windower.add_to_chat(8,'GearSwap (Debug Mode): Hitting Aftercast without detecting an entry in command_registry')
		end
	elseif readies[act.category] and prefix == 'pet_' and act.targets[1].actions[1].message ~= 0 then -- Entry for pet midcast. Excludes the second packet of "Out of range" BPs.
		ts = mk_command_registry_entry(spell,spell.target.id)
		refresh_globals()
		equip_sets('pet_midcast',ts,spell)
	end
end



-----------------------------------------------------------------------------------
--Name: inc_action_message(arr)
--Desc: Calls midcast or aftercast functions as appropriate in response to incoming
--      action message packets.
--Args:
---- arr - Action message packet arguments (described on the dev wiki):
  -- actor_id,target_id,param_1,param_2,param_3,actor_index,target_index,message_id)
-----------------------------------------------------------------------------------
--Returns:
---- none
-----------------------------------------------------------------------------------
function inc_action_message(arr)
	if debugging >= 1 then windower.debug('action message') end
	if gearswap_disabled then return end
	if T{6,20,113,406,605,646}:contains(arr.message_id) then
		-- If a spell's target is defeated or falls to the ground
		local ts,tab = delete_command_registry_by_id(arr.target_id)
		if tab and tab.spell and tab.spell.prefix == '/pet' then 
			equip_sets('pet_aftercast',nil,tab.spell)
		elseif tab and tab.spell then
			equip_sets('aftercast',nil,tab.spell)
		end
		return
	end
	
	local tempplay = windower.ffxi.get_player()
	local prefix = ''
	if arr.actor_id ~= tempplay.id then
		if tempplay.pet_index then
			if arr.actor_id ~= windower.ffxi.get_mob_by_index(tempplay.pet_index).id then
				return
			else
				prefix = 'pet_'
			end
		else
			return
		end
	end
	
	if unable_to_use:contains(arr.message_id) and arr.actor_id == player.id then
		if logging then	logit(logfile,'\n\n'..tostring(os.clock)..'(195) Event Action Message: '..tostring(message_id)..' Interrupt') end
		ts,tab = find_command_registry_by_time('player')
		
		tab.spell.interrupted = true
		tab.spell.action_type = 'Interruption'
		refresh_globals()
		equip_sets(prefix..'aftercast',ts,tab.spell)
	elseif unable_to_use:contains(arr.message_id) and debugging >= 1 then
		windower.add_to_chat(8,'Handled Action message received with a target other than yourself: '..tostring(dialog[arr.message_id].english)..' '..tostring(windower.ffxi.get_mob_by_id(actor_id).name))
	end
end