/obj/machinery/teleport
	name = "teleport"
	icon = 'icons/obj/machines/teleporter.dmi'
	density = TRUE

/obj/machinery/teleport/hub
	name = "teleporter hub"
	desc = "It's the hub of a teleporting machine."
	icon_state = "tele0"
	base_icon_state = "tele"
	use_power = IDLE_POWER_USE
	idle_power_usage = IDLE_DRAW_MINIMAL
	active_power_usage = ACTIVE_DRAW_HIGH
	circuit = /obj/item/circuitboard/machine/teleporter_hub
	var/accuracy = 0
	var/obj/machinery/teleport/station/power_station
	var/calibrated //Calibration prevents mutation

/obj/machinery/teleport/hub/Initialize()
	. = ..()
	link_power_station()

/obj/machinery/teleport/hub/Destroy()
	if (power_station)
		power_station.teleporter_hub = null
		power_station.engaged = FALSE
		power_station = null
	return ..()

/obj/machinery/teleport/hub/RefreshParts()
	var/A = 0
	for(var/obj/item/stock_parts/matter_bin/M in component_parts)
		A += M.rating
	accuracy = A

/obj/machinery/teleport/hub/examine(mob/user)
	. = ..()
	if(in_range(user, src) || isobserver(user))
		. += span_notice("The status display reads: Probability of malfunction decreased by <b>[(accuracy*25)-25]%</b>.")

//Instead of recursive processing, this now signals the power source, if it exists, to link up with the other pieces.
/obj/machinery/teleport/hub/proc/link_power_station()
	if(!power_station) //This only runs on initialize() but maybe it will not in the future.
		var/obj/machinery/teleport/station/unlinked_station //Temporary variables are good so we don't have to reset them all the time.
		for(var/direction in GLOB.cardinals)
			unlinked_station = locate(/obj/machinery/teleport/station, get_step(src, direction))
			if(unlinked_station && unlinked_station.link_console_and_hub(unlinked_hub = src)) //Signal that this hub requires a power source.
				power_station = unlinked_station //This is not handled by the power source if linking directly.
				break //Only break if it actually links it to the power source.

/obj/machinery/teleport/hub/Bumped(atom/movable/AM)
	if(is_centcom_level(src))
		to_chat(AM, span_warning("You can't use this here!"))
		return
	if(is_ready())
		teleport(AM)

/obj/machinery/teleport/hub/attackby(obj/item/W, mob/user, params)
	if(default_deconstruction_screwdriver(user, "tele-o", "tele0", W))
		if(power_station && power_station.engaged)
			power_station.engaged = 0 //hub with panel open is off, so the station must be informed.
			update_appearance()
		return
	if(default_deconstruction_crowbar(W))
		return
	return ..()

/obj/machinery/teleport/hub/proc/teleport(atom/movable/M as mob|obj, turf/T)
	var/obj/machinery/computer/teleporter/com = power_station.teleporter_console
	if (QDELETED(com))
		return
	if (QDELETED(com.target))
		com.target = null
		visible_message(span_alert("Cannot authenticate locked on coordinates. Please reinstate coordinate matrix."))
		return
	if (ismovable(M))
		if(do_teleport(M, com.target, channel = TELEPORT_CHANNEL_BLUESPACE, restrain_vlevel = FALSE))
			use_power(5000)
			if(!calibrated && prob(30 - ((accuracy) * 10))) //oh dear a problem
				if(ishuman(M))//don't remove people from the round randomly you jerks
					var/mob/living/carbon/human/human = M
					if(human.dna && human.dna.species.id == "human")
						to_chat(M, span_hear("You hear a buzzing in your ears."))
						human.set_species(/datum/species/fly)
						log_game("[human] ([key_name(human)]) was turned into a fly person")

					human.apply_effect((rand(120 - accuracy * 40, 180 - accuracy * 60)), EFFECT_IRRADIATE, 0)
			calibrated = 0
	return

/obj/machinery/teleport/hub/update_icon_state()
	icon_state = "[base_icon_state][panel_open ? "-o" : (is_ready() ? 1 : 0)]"
	return ..()

/obj/machinery/teleport/hub/proc/is_ready()
	. = !panel_open && !(machine_stat & (BROKEN|NOPOWER)) && power_station && power_station.engaged && !(power_station.machine_stat & (BROKEN|NOPOWER))

/obj/machinery/teleport/hub/syndicate/Initialize()
	. = ..()
	component_parts += new /obj/item/stock_parts/matter_bin/super(null)
	RefreshParts()


/obj/machinery/teleport/station
	name = "teleporter station"
	desc = "The power control station for a bluespace teleporter. Used for toggling power."
	icon_state = "controller"
	base_icon_state = "controller"
	use_power = IDLE_POWER_USE
	idle_power_usage = IDLE_DRAW_MINIMAL
	active_power_usage = ACTIVE_DRAW_HIGH
	circuit = /obj/item/circuitboard/machine/teleporter_station
	var/engaged = FALSE
	var/obj/machinery/computer/teleporter/teleporter_console
	var/obj/machinery/teleport/hub/teleporter_hub
	var/list/linked_stations = list()
	var/efficiency = 0

/obj/machinery/teleport/station/Initialize()
	. = ..()
	link_console_and_hub()

/obj/machinery/teleport/station/RefreshParts()
	var/E
	for(var/obj/item/stock_parts/capacitor/C in component_parts)
		E += C.rating
	efficiency = E - 1

/obj/machinery/teleport/station/examine(mob/user)
	. = ..()
	if(!panel_open)
		. += span_notice("The panel is <i>screwed</i> in, obstructing the linking device and wiring panel.")
	else
		. += span_notice("The <i>linking</i> device is now able to be <i>scanned</i> with a multitool.")
	if(in_range(user, src) || isobserver(user))
		. += span_notice("The status display reads: This station can be linked to <b>[efficiency]</b> other station(s).")

/obj/machinery/teleport/station/proc/link_console_and_hub(obj/machinery/teleport/hub/unlinked_hub, obj/machinery/computer/teleporter/unlinked_console)
	if(!teleporter_hub)
		if(unlinked_hub) //We have a hub already.
			teleporter_hub = unlinked_hub
			. = TRUE //Only matters if we are directly linking via arguments passed.
		else //Otherwise we look for one.
			for(var/direction in GLOB.cardinals)
				unlinked_hub = locate(/obj/machinery/teleport/hub, get_step(src, direction))
				if(unlinked_hub && !unlinked_hub.power_station) //To make sure they aren't already linked to another set.
					teleporter_hub = unlinked_hub
					teleporter_hub.power_station = src
					break

	if(!teleporter_console)
		if(unlinked_console)
			teleporter_console = unlinked_console
			. = TRUE
		else
			for(var/direction in GLOB.cardinals)
				unlinked_console = locate(/obj/machinery/computer/teleporter, get_step(src, direction))
				if(unlinked_console && !unlinked_console.power_station)
					teleporter_console = unlinked_console
					teleporter_console.power_station = src
					break
			//A little copypasta but a lot easier to digest than the previous iteration.
			if(teleporter_hub && !teleporter_console) //Hub present, no console detected. Let's try looking for a console next to the hub.
				for(var/direction in GLOB.cardinals)
					unlinked_console = locate(/obj/machinery/computer/teleporter, get_step(teleporter_hub, direction))
					if(unlinked_console && !unlinked_console.power_station)
						teleporter_console = unlinked_console
						teleporter_console.power_station = src
						break

/obj/machinery/teleport/station/Destroy()
	if(teleporter_hub)
		teleporter_hub.power_station = null
		teleporter_hub.update_appearance()
		teleporter_hub = null
	if (teleporter_console)
		teleporter_console.power_station = null
		teleporter_console = null
	return ..()

/obj/machinery/teleport/station/attackby(obj/item/W, mob/user, params)
	if(W.tool_behaviour == TOOL_MULTITOOL)
		if(!multitool_check_buffer(user, W))
			return
		var/obj/item/multitool/M = W
		if(panel_open)
			M.buffer = src
			to_chat(user, span_notice("You download the data to the [W.name]'s buffer."))
		else
			if(M.buffer && istype(M.buffer, /obj/machinery/teleport/station) && M.buffer != src)
				if(linked_stations.len < efficiency)
					linked_stations.Add(M.buffer)
					M.buffer = null
					to_chat(user, span_notice("You upload the data from the [W.name]'s buffer."))
				else
					to_chat(user, span_alert("This station can't hold more information, try to use better parts."))
		return
	else if(default_deconstruction_screwdriver(user, "controller-o", "controller", W))
		update_appearance()
		return

	else if(default_deconstruction_crowbar(W))
		return
	else
		return ..()

/obj/machinery/teleport/station/interact(mob/user)
	toggle(user)

/obj/machinery/teleport/station/proc/toggle(mob/user)
	if(machine_stat & (BROKEN|NOPOWER) || !teleporter_hub || !teleporter_console)
		return
	if (teleporter_console.target)
		if(teleporter_hub.panel_open || teleporter_hub.machine_stat & (BROKEN|NOPOWER))
			to_chat(user, span_alert("The teleporter hub isn't responding."))
		else
			engaged = !engaged
			use_power(5000)
			to_chat(user, span_notice("Teleporter [engaged ? "" : "dis"]engaged!"))
	else
		to_chat(user, span_alert("No target detected."))
		engaged = FALSE
	teleporter_hub.update_appearance()
	add_fingerprint(user)

/obj/machinery/teleport/station/power_change()
	. = ..()
	if(teleporter_hub)
		teleporter_hub.update_appearance()

/obj/machinery/teleport/station/update_icon_state()
	if(panel_open)
		icon_state = "[base_icon_state]-o"
		return ..()
	if(machine_stat & (BROKEN|NOPOWER))
		icon_state = "[base_icon_state]-p"
		return ..()
	if(teleporter_console?.calibrating)
		icon_state = "[base_icon_state]-c"
		return ..()
	icon_state = base_icon_state
	return ..()
