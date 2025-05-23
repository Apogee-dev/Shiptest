#define HEATER_MODE_STANDBY "standby"
#define HEATER_MODE_HEAT "heat"
#define HEATER_MODE_COOL "cool"

/obj/machinery/space_heater
	anchored = FALSE
	density = TRUE
	interaction_flags_machine = INTERACT_MACHINE_WIRES_IF_OPEN | INTERACT_MACHINE_ALLOW_SILICON | INTERACT_MACHINE_OPEN
	icon = 'icons/obj/atmos.dmi'
	icon_state = "sheater-off"
	base_icon_state = "sheater"
	name = "space heater"
	desc = "Made by Space Amish using traditional space techniques, this heater/cooler is guaranteed* not to set the air on fire. Warranty void if used in engines."
	max_integrity = 250
	armor = list("melee" = 0, "bullet" = 0, "laser" = 0, "energy" = 0, "bomb" = 0, "bio" = 100, "rad" = 100, "fire" = 80, "acid" = 10)
	circuit = /obj/item/circuitboard/machine/space_heater
	/// We don't use area power, we always use the cell
	use_power = NO_POWER_USE
	interacts_with_air = TRUE
	var/obj/item/stock_parts/cell/cell
	var/on = FALSE
	var/mode = HEATER_MODE_STANDBY
	var/setMode = "auto" // Anything other than "heat" or "cool" is considered auto.
	var/targetTemperature = T20C
	var/heatingPower = 20000
	var/efficiency = 20000
	var/temperatureTolerance = 1
	var/settableTemperatureMedian = 30 + T0C
	var/settableTemperatureRange = 30

/obj/machinery/space_heater/get_cell()
	return cell

/obj/machinery/space_heater/Initialize()
	. = ..()
	cell = new(src)
	update_appearance()

/obj/machinery/space_heater/on_construction()
	qdel(cell)
	cell = null
	panel_open = TRUE
	update_appearance()
	return ..()

/obj/machinery/space_heater/on_deconstruction()
	if(cell)
		component_parts += cell
		cell = null
	return ..()

/obj/machinery/space_heater/examine(mob/user)
	. = ..()
	. += "\The [src] is [on ? "on" : "off"], and the hatch is [panel_open ? "open" : "closed"]."
	if(cell)
		. += "The charge meter reads [cell ? round(cell.percent(), 1) : 0]%."
	else
		. += "There is no power cell installed."
	if(in_range(user, src) || isobserver(user))
		. += span_notice("The status display reads: Temperature range at <b>[settableTemperatureRange]°C</b>.<br>Heating power at <b>[heatingPower*0.001]kJ</b>.<br>Power consumption at <b>[(efficiency*-0.0025)+150]%</b>.") //100%, 75%, 50%, 25%

/obj/machinery/space_heater/update_icon_state()
	icon_state = "[base_icon_state]-[on ? mode : "off"]"
	return ..()

/obj/machinery/space_heater/update_overlays()
	. = ..()

	if(panel_open)
		. += "[base_icon_state]-open"

/obj/machinery/space_heater/process_atmos(seconds_per_tick) //TODO figure out seconds_per_tick
	if(!on || !is_operational)
		if (on) // If it's broken, turn it off too
			on = FALSE
		return PROCESS_KILL

	if(cell && cell.charge > 0)
		var/turf/L = loc
		if(!istype(L))
			if(mode != HEATER_MODE_STANDBY)
				mode = HEATER_MODE_STANDBY
				update_appearance()
			return

		var/datum/gas_mixture/env = L.return_air()

		var/newMode = HEATER_MODE_STANDBY
		if(setMode != HEATER_MODE_COOL && env.return_temperature() < targetTemperature - temperatureTolerance)
			newMode = HEATER_MODE_HEAT
		else if(setMode != HEATER_MODE_HEAT && env.return_temperature() > targetTemperature + temperatureTolerance)
			newMode = HEATER_MODE_COOL

		if(mode != newMode)
			mode = newMode
			update_appearance()

		if(mode == HEATER_MODE_STANDBY)
			return

		var/heat_capacity = env.heat_capacity()
		var/requiredEnergy = abs(env.return_temperature() - targetTemperature) * heat_capacity
		requiredEnergy = min(requiredEnergy, heatingPower * seconds_per_tick)

		if(requiredEnergy < 1)
			return

		var/deltaTemperature = requiredEnergy / heat_capacity
		if(mode == HEATER_MODE_COOL)
			deltaTemperature *= -1
		if(deltaTemperature)
			env.set_temperature(env.return_temperature() + deltaTemperature)
			air_update_turf()
		cell.use(requiredEnergy / efficiency)
	else
		on = FALSE
		update_appearance()
		return PROCESS_KILL

/obj/machinery/space_heater/RefreshParts()
	var/laser = 0
	var/cap = 0
	for(var/obj/item/stock_parts/micro_laser/M in component_parts)
		laser += M.rating
	for(var/obj/item/stock_parts/capacitor/M in component_parts)
		cap += M.rating

	heatingPower = laser * 20000

	settableTemperatureRange = cap * 30
	efficiency = (cap + 1) * 10000

	targetTemperature = clamp(targetTemperature,
		max(settableTemperatureMedian - settableTemperatureRange, TCMB),
		settableTemperatureMedian + settableTemperatureRange)

/obj/machinery/space_heater/emp_act(severity)
	. = ..()
	if(machine_stat & (NOPOWER|BROKEN) || . & EMP_PROTECT_CONTENTS)
		return
	if(cell)
		cell.emp_act(severity)

/obj/machinery/space_heater/attackby(obj/item/I, mob/user, params)
	add_fingerprint(user)
	if(default_unfasten_wrench(user, I))
		return
	else if(istype(I, /obj/item/stock_parts/cell))
		if(panel_open)
			if(cell)
				to_chat(user, span_warning("There is already a power cell inside!"))
				return
			else if(!user.transferItemToLoc(I, src))
				return
			cell = I
			I.add_fingerprint(usr)

			user.visible_message(span_notice("\The [user] inserts a power cell into \the [src]."), span_notice("You insert the power cell into \the [src]."))
			SStgui.update_uis(src)
		else
			to_chat(user, span_warning("The hatch must be open to insert a power cell!"))
			return
	else if(I.tool_behaviour == TOOL_SCREWDRIVER)
		panel_open = !panel_open
		user.visible_message(span_notice("\The [user] [panel_open ? "opens" : "closes"] the hatch on \the [src]."), span_notice("You [panel_open ? "open" : "close"] the hatch on \the [src]."))
		update_appearance()
	else if(default_deconstruction_crowbar(I))
		return
	else
		return ..()

/obj/machinery/space_heater/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "SpaceHeater", name)
		ui.open()

/obj/machinery/space_heater/ui_data()
	var/list/data = list()
	data["open"] = panel_open
	data["on"] = on
	data["mode"] = setMode
	data["hasPowercell"] = !!cell
	if(cell)
		data["powerLevel"] = round(cell.percent(), 1)
	data["targetTemp"] = round(targetTemperature - T0C, 1)
	data["minTemp"] = max(settableTemperatureMedian - settableTemperatureRange - T0C, TCMB)
	data["maxTemp"] = settableTemperatureMedian + settableTemperatureRange - T0C

	var/turf/L = get_turf(loc)
	var/curTemp
	if(istype(L))
		var/datum/gas_mixture/env = L.return_air()
		curTemp = env.return_temperature()
	else if(isturf(L))
		curTemp = L.return_temperature()
	if(isnull(curTemp))
		data["currentTemp"] = "N/A"
	else
		data["currentTemp"] = round(curTemp - T0C, 1)
	return data

/obj/machinery/space_heater/ui_act(action, params)
	. = ..()
	if(.)
		return

	switch(action)
		if("power")
			on = !on
			mode = HEATER_MODE_STANDBY
			usr.visible_message(span_notice("[usr] switches [on ? "on" : "off"] \the [src]."), span_notice("You switch [on ? "on" : "off"] \the [src]."))
			update_appearance()
			if (on)
				SSair.start_processing_machine(src)
			. = TRUE
		if("mode")
			setMode = params["mode"]
			. = TRUE
		if("target")
			if(!panel_open)
				return
			var/target = params["target"]
			if(text2num(target) != null)
				target= text2num(target) + T0C
				. = TRUE
			if(.)
				targetTemperature = clamp(round(target),
					max(settableTemperatureMedian - settableTemperatureRange, TCMB),
					settableTemperatureMedian + settableTemperatureRange)
		if("eject")
			if(panel_open && cell)
				cell.forceMove(drop_location())
				cell = null
				. = TRUE

#undef HEATER_MODE_STANDBY
#undef HEATER_MODE_HEAT
#undef HEATER_MODE_COOL
