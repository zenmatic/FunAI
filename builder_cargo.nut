class BuildCargoLine extends Task {
	
	static CARGO_MIN_DISTANCE = 30;
	static CARGO_MAX_DISTANCE = 75;
	static TILES_PER_DAY = 1;
	static CARGO_STATION_LENGTH = 3;
	
	static bannedCargo = [];
	static routes = [];
	static routesCalculated = Flag();
	
	constructor(parentTask=null) {
		Task.constructor(parentTask, null);
	}
	
	function _tostring() {
		return "BuildCargoLine";
	}
	
	function Run() {
		if (routes.len() == 0 && !routesCalculated.Get()) {
			Debug("Calculating best cargo routes...");
			SetConstructionSign(AIMap.GetTileIndex(1, COMPANY), this);
			SetSecondarySign("Evaluating routes...");
			
			routesCalculated.Set(true);
			routes.extend(CalculateRoutes());
			
			ClearSecondarySign();
		}
		
		if (!subtasks) {
			if (routes.len() == 0) {
				throw TaskFailedException("no cargo routes");
			}
			
			// delay for a random time, so different ChooChoos run out of sync
			// that way, they each get their choice from the best cargo routes
			// after that, the main building routine is random anyway
			AIController.Sleep(1 + abs(AIBase.Rand() % TICKS_PER_DAY));
			
			local route = routes[0];
			routes.remove(0);
			
			local cargo = route.cargo;
			local a = route.from;
			local b = route.to;
			
			local maxDistance = min(CARGO_MAX_DISTANCE, MaxDistance(cargo, CARGO_STATION_LENGTH));
			local railType = SelectRailType(cargo);
			AIRail.SetCurrentRailType(railType);
			
			if (AIIndustry.GetAmountOfStationsAround(a) > 0) {
				Debug(AIIndustry.GetName(a), "is already being served");
				throw TaskRetryException();
			}
						
			Debug("Selected:", AICargo.GetCargoLabel(cargo), "from", AIIndustry.GetName(a), "to", AIIndustry.GetName(b));
			
			// [siteA, rotA, dirA, siteB, rotB, dirB]
			local sites = FindStationSites(a, b);
			if (sites == null) {
				Debug("Cannot build both stations");
				throw TaskRetryException();
			}
			
			local siteA = sites[0];
			local rotA = sites[1];
			local dirA = sites[2];
			local stationA = TerminusStation(siteA, rotA, CARGO_STATION_LENGTH);
			
			local siteB = sites[3];
			local rotB = sites[4];
			local dirB = sites[5];
			local stationB = TerminusStation(siteB, rotB, CARGO_STATION_LENGTH);
			
			// double track cargo lines discarded: we just use them for cheap starting income
			// old strategy: build the first track and two trains first, which can then finance the upgrade to double track
			//local reserved = stationA.GetReservedEntranceSpace();
			//reserved.extend(stationB.GetReservedExitSpace());
			//local exitA = Swap(TerminusStation(siteA, rotA, CARGO_STATION_LENGTH).GetEntrance());
			//local exitB = TerminusStation(siteB, rotB, CARGO_STATION_LENGTH).GetEntrance();
			//local firstTrack = BuildTrack(stationA.GetExit(), stationB.GetEntrance(), reserved, SignalMode.NONE, network);
			
			local network = Network(railType, CARGO_STATION_LENGTH, MIN_DISTANCE, maxDistance);
			subtasks = [
				// location, direction, network, atIndustry, toIndustry, cargo isSource, platformLength
				BuildCargoStation(this, siteA, dirA, network, a, b, cargo, true, CARGO_STATION_LENGTH),
				BuildCargoStation(this, siteB, dirB, network, b, a, cargo, false, CARGO_STATION_LENGTH),
				BuildTrack(this, Swap(stationA.GetEntrance()), stationB.GetEntrance(), [], SignalMode.NONE, network, BuildTrack.FAST),
				//firstTrack,
				BuildTrains(this, siteA, network, cargo, AIOrder.OF_FULL_LOAD_ANY),
				//BuildTrains(this, siteA, network, cargo, AIOrder.OF_FULL_LOAD_ANY),
				//BuildTrack(this, Swap(stationA.GetEntrance()), Swap(stationB.GetExit()), [], SignalMode.BACKWARD, network),
				//BuildSignals(this, firstTrack, SignalMode.FORWARD),
			];
		}
		
		RunSubtasks();
	}
	
	function SelectRailType(cargo) {
		// select a rail type for which we can build a locomotive that can pull wagons for the desired cargo
		local railTypes = AIRailTypeList();
		railTypes.Valuate(CarriesCargo, cargo);
		railTypes.KeepValue(1);
		railTypes.Valuate(AIRail.GetBuildCost, AIRail.BT_TRACK);
		railTypes.KeepAboveValue(0);	// filter out NuTracks planning tracks, which are free
		railTypes.KeepBottom(1);		// use the cheap stuff for cargo
		if (railTypes.IsEmpty()) {
			bannedCargo.append(cargo);
			throw TaskFailedException("no rail type for " + AICargo.GetCargoLabel(cargo));
		} else {
			return railTypes.Begin();
		}
	}
	
	function CarriesCargo(railType, cargo) {
		local engineList = AIEngineList(AIVehicle.VT_RAIL);
		engineList.Valuate(AIEngine.IsWagon);
		engineList.KeepValue(0);
		engineList.Valuate(AIEngine.CanRunOnRail, railType);
		engineList.KeepValue(1);
		engineList.Valuate(AIEngine.HasPowerOnRail, railType);
		engineList.KeepValue(1);
		engineList.Valuate(AIEngine.CanPullCargo, cargo);
		engineList.KeepValue(1);
		return engineList.IsEmpty() ? 0 : 1;
	}
	
	function SelectCargo() {
		local cargoList = AICargoList();
		
		// haven't tried to use it before, and failed
		cargoList.RemoveList(ArrayToList(bannedCargo));
		
		// no passengers, mail or valuables
		foreach (cc in [AICargo.CC_PASSENGERS, AICargo.CC_MAIL, AICargo.CC_EXPRESS, AICargo.CC_ARMOURED]) { 
			cargoList.Valuate(AICargo.HasCargoClass, cc);
			cargoList.KeepValue(0);
		}
		
		// is actually available (primaries only)
		cargoList.Valuate(IsAvailable);
		cargoList.KeepValue(1);
		
		// decent profit
		cargoList.Valuate(AICargo.GetCargoIncome, CARGO_MAX_DISTANCE, CARGO_MAX_DISTANCE/TILES_PER_DAY);
		cargoList.KeepTop(3);
		
		if (cargoList.IsEmpty()) {
			throw TaskFailedException("No suitable cargo");
		}
		
		// pick one at random
		cargoList.Valuate(AIBase.RandItem);
		cargoList.KeepTop(1);
		return cargoList.Begin();
	}
	
	/**
	 * See if a cargo is produced anywhere in reasonable quantities.
	 */
	function IsAvailable(cargo) {
		local industries = AIIndustryList_CargoProducing(cargo);
		industries.Valuate(AIIndustry.GetLastMonthProduction, cargo);
		industries.KeepAboveValue(50);
		return !industries.IsEmpty();
	}
	
	function SelectIndustries(cargo, maxDistance) {
		local producers = AIIndustryList_CargoProducing(cargo);
		
		// we want decent production
		producers.Valuate(AIIndustry.GetLastMonthProduction, cargo);
		producers.KeepAboveValue(80);
		
		// and no competition, nor an earlier station of our own
		producers.Valuate(AIIndustry.GetAmountOfStationsAround);
		producers.KeepValue(0);
		
		// find a random producer/consumer pair that's within our target distance
		producers.Valuate(AIBase.RandItem);
		producers.Sort(AIList.SORT_BY_VALUE, true);
		for (local producer = producers.Begin(); !producers.IsEnd(); producer = producers.Next()) {
			local consumers = AIIndustryList_CargoAccepting(cargo);
			consumers.Valuate(AIIndustry.GetDistanceManhattanToTile, AIIndustry.GetLocation(producer));
			consumers.KeepAboveValue(CARGO_MIN_DISTANCE);
			consumers.KeepBelowValue(maxDistance);
			
			for (local consumer = consumers.Begin(); consumers.HasNext(); consumer = consumers.Next()) {
				if (FindStationSites(producer, consumer)) {
					return [producer, consumer];
				}
			}
		}
		
		// can't find a route for this cargo
		Warning("No route for " + AICargo.GetCargoLabel(cargo));
		bannedCargo.append(cargo);
		throw TaskRetryException();
	}
	
	function FindStationSites(a, b) {
		local locA = AIIndustry.GetLocation(a);
		local locB = AIIndustry.GetLocation(b);
		
		local nameA = AIIndustry.GetName(a);
		local dirA = StationDirection(locA, locB);
		local rotA = BuildTerminusStation.StationRotationForDirection(dirA);
		//local siteA = FindIndustryStationSite(a, true, rotA, locB, CARGO_STATION_LENGTH + 3, 2);
		local siteA = FindIndustryStationSite(a, true, rotA, locB);

		local nameB = AIIndustry.GetName(b);
		local dirB = StationDirection(locB, locA);
		local rotB = BuildTerminusStation.StationRotationForDirection(dirB);
		//local siteB = FindIndustryStationSite(b, false, rotB, locA, CARGO_STATION_LENGTH + 3, 2);
		local siteB = FindIndustryStationSite(b, false, rotB, locA);
		
		if (siteA && siteB) {
			return [siteA, rotA, dirA, siteB, rotB, dirB];
		} else {
			Debug("Cannot build a station at " + (siteA ? nameB : nameA));
			return null;
		}
	}
	
	/**
	 * Find a site for a station at the given industry.
	 */
	function FindIndustryStationSite(industry, producing, stationRotation, destination) {
		local location = AIIndustry.GetLocation(industry);
		local area = producing ? AITileList_IndustryProducing(industry, RAIL_STATION_RADIUS) : AITileList_IndustryAccepting(industry, RAIL_STATION_RADIUS);

		// room for a station
		area.Valuate(IsBuildableRectangle, stationRotation, [0, -1], [1, CARGO_STATION_LENGTH + 1], true);
		area.KeepValue(1);
		
		// pick the tile farthest from the destination for increased profit
		//area.Valuate(AITile.GetDistanceManhattanToTile, destination);
		//area.KeepTop(10);
		
		// pick the tile closest to the industry for looks
		area.Valuate(AITile.GetDistanceManhattanToTile, location);
		area.KeepBottom(1);
		
		return area.IsEmpty() ? null : area.Begin();
	}
}

class BuildNamedCargoLine extends BuildCargoLine {

	producer = null;
	consumer = null;
	cargo = null;

	constructor(parentTask, producer, consumer, cargo) {
		Task.constructor(parentTask, null);
		this.producer = producer;
		this.consumer = consumer;
		this.cargo = cargo;
		Debug("cargo is ", cargo);
	}

	function _tostring() {
		return "BuildNamedCargoLine";
	}

	function Run() {
		if (routes.len() == 0) {
			local r = CargoRoute(producer, consumer, cargo)
			this.routes.append(r);
		}
		
		if (!subtasks) {
			if (routes.len() == 0) {
				throw TaskFailedException("no cargo routes");
			}
			
			local route = routes[0];
			routes.remove(0);
			
			local cargo = route.cargo;
			local a = route.from;
			local b = route.to;
			
			local maxDistance = min(CARGO_MAX_DISTANCE, MaxDistance(cargo, CARGO_STATION_LENGTH));
			local railType = SelectRailType(cargo);
			AIRail.SetCurrentRailType(railType);
			
			/*
			if (AIIndustry.GetAmountOfStationsAround(a) > 0) {
				Debug(AIIndustry.GetName(a), "is already being served");
				throw TaskRetryException();
			}
			*/

			Debug("Selected:", AICargo.GetCargoLabel(cargo), "from", AIIndustry.GetName(a), "to", AIIndustry.GetName(b));
			
			// [siteA, rotA, dirA, siteB, rotB, dirB]
			local sites = FindStationSites(a, b);
			if (sites == null) {
				Debug("Cannot build both stations");
				throw TaskRetryException();
			}
			
			local siteA = sites[0];
			local rotA = sites[1];
			local dirA = sites[2];
			local stationA = TerminusStation(siteA, rotA, CARGO_STATION_LENGTH);
			local depotA = stationA.GetRoadDepot();
			
			local siteB = sites[3];
			local rotB = sites[4];
			local dirB = sites[5];
			local stationB = TerminusStation(siteB, rotB, CARGO_STATION_LENGTH);
			local depotB = stationB.GetRoadDepot();
			
			// double track cargo lines discarded: we just use them for cheap starting income
			// old strategy: build the first track and two trains first, which can then finance the upgrade to double track
			//local reserved = stationA.GetReservedEntranceSpace();
			//reserved.extend(stationB.GetReservedExitSpace());
			//local exitA = Swap(TerminusStation(siteA, rotA, CARGO_STATION_LENGTH).GetEntrance());
			//local exitB = TerminusStation(siteB, rotB, CARGO_STATION_LENGTH).GetEntrance();
			//local firstTrack = BuildTrack(stationA.GetExit(), stationB.GetEntrance(), reserved, SignalMode.NONE, network);
			
			local network = Network(railType, CARGO_STATION_LENGTH, MIN_DISTANCE, maxDistance);
			local fromFlags = AIOrder.OF_NONE;
			local toFlags = fromFlags;
			subtasks = [
				// location, direction, network, atIndustry, toIndustry, cargo isSource, platformLength
				BuildCargoStation(this, siteA, dirA, network, a, b, cargo, true, CARGO_STATION_LENGTH),
				BuildCargoStation(this, siteB, dirB, network, b, a, cargo, false, CARGO_STATION_LENGTH),
				BuildTrack(this, Swap(stationA.GetEntrance()), stationB.GetEntrance(), [], SignalMode.NONE, network, BuildTrack.FAST),
				//firstTrack,
				BuildTrain2(siteA, siteB, depotA, depotB, network, fromFlags, toFlags, cargo),
				//BuildTrains(this, siteA, network, cargo, AIOrder.OF_FULL_LOAD_ANY),
				//BuildTrains(this, siteA, network, cargo, AIOrder.OF_FULL_LOAD_ANY),
				//BuildTrack(this, Swap(stationA.GetEntrance()), Swap(stationB.GetExit()), [], SignalMode.BACKWARD, network),
				//BuildSignals(this, firstTrack, SignalMode.FORWARD),
			];
		}
		
		RunSubtasks();

	}

}

class BuildTransferCargoLine extends BuildCargoLine {
	producer_info = null;
	consumer_info = null;
	cargo = null;

	constructor(parentTask, producer_info, consumer_info, cargo) {
		Task.constructor(parentTask, null);
		/*
		producer_info = {
			id = industry or town ID,
			type = either AISubsidy.SPT_TOWN or AISubsidy.SPT_INDUSTRY
		}
		*/
		this.producer_info = producer_info;
		this.consumer_info = consumer_info;
		this.cargo = cargo;
		Debug("cargo is ", cargo);

		SetAttributes(this.producer_info);
		SetAttributes(this.consumer_info);

		PrintAttributes("producer_info", this.producer_info);
		PrintAttributes("consumer_info", this.consumer_info);
	}

	function _tostring() {
		return "BuildTransferLine";
	}

	function PrintAttributes(title, info) {
		local k,v;
		Debug(title, " table:");
		foreach (k,v in info) {
			Debug(k," ",v);
		}
	}

	function SetAttributes(info) {
		if (info.type == AISubsidy.SPT_TOWN) {
			info.name <- AITown.GetName(info.id);
			info.loc <- AITown.GetLocation(info.id);
		} else {
			info.name <- AIIndustry.GetName(info.id);
			info.loc <- AIIndustry.GetLocation(info.id);
		}
	}

	function Run() {
		
		local maxDistance = min(CARGO_MAX_DISTANCE, MaxDistance(cargo, CARGO_STATION_LENGTH));
		local railType = SelectRailType(cargo);
		AIRail.SetCurrentRailType(railType);
		
		Debug("Selected:", AICargo.GetCargoLabel(cargo), "from", producer_info.name, "to", consumer_info.name);

		local a = producer_info.id;
		local b = consumer_info.id;
		
		// [siteA, rotA, dirA, siteB, rotB, dirB]
		local sites = FindStationSites(a, b);
		if (sites == null) {
			Debug("Cannot build both stations");
			throw TaskRetryException();
		}
		
		local siteA = sites[0];
		local rotA = sites[1];
		local dirA = sites[2];
		local stationA = TerminusStation(siteA, rotA, CARGO_STATION_LENGTH);
		local depotA = stationA.GetRoadDepot();
		
		local siteB = sites[3];
		local rotB = sites[4];
		local dirB = sites[5];
		local stationB = TerminusStation(siteB, rotB, CARGO_STATION_LENGTH);
		local depotB = stationB.GetRoadDepot();

		local network = Network(railType, CARGO_STATION_LENGTH, MIN_DISTANCE, maxDistance);
		local fromFlags = AIOrder.OF_NONE;
		local toFlags = fromFlags;

		// if transfer, build city stop, then transfer station
		// link city stop to station
		// if direct station, build
		// link stations

		subtasks = [];

		if (producer_info.type == AISubsidy.SPT_TOWN) {
			Debug(producer_info.name, " is a town");
			siteA = FindStationSite(producer_info.id, rotA, dirA);
			Debug("siteA is ", siteA);
			subtasks.append(BuildTransferCargoLine(this, producer_info,
				consumer_info, cargo));
		} else {
			subtasks.append(BuildCargoStation(this, siteA, dirA, network, a, b, cargo, true, CARGO_STATION_LENGTH));
		}

		if (consumer_info.type == AISubsidy.SPT_TOWN) {
			Debug(consumer_info.name, " is a town");
			siteB = FindStationSite(consumer_info.id, rotB, dirB);
			Debug("siteB is ", siteB);
			subtasks.append(BuildTransferCargoLine(this, consumer_info,
				producer_info, cargo));
		} else {
			subtasks.append(BuildCargoStation(this, siteB, dirB, network, b, a, cargo, false, CARGO_STATION_LENGTH));
		}

		subtasks.extend([
			// location, direction, network, atIndustry, toIndustry, cargo isSource, platformLength
			BuildTrack(this, Swap(stationA.GetEntrance()), stationB.GetEntrance(), [], SignalMode.NONE, network, BuildTrack.FAST),
			//firstTrack,
			BuildTrain2(siteA, siteB, depotA, depotB, network, fromFlags, toFlags, cargo),
			//BuildTrains(this, siteA, network, cargo, AIOrder.OF_FULL_LOAD_ANY),
			//BuildTrains(this, siteA, network, cargo, AIOrder.OF_FULL_LOAD_ANY),
			//BuildTrack(this, Swap(stationA.GetEntrance()), Swap(stationB.GetExit()), [], SignalMode.BACKWARD, network),
			//BuildSignals(this, firstTrack, SignalMode.FORWARD),
		]);
		
		RunSubtasks();
	}

	function BuildStations(info) {
		if (info.type == AISubsidy.SPT_TOWN) {
			if (FindStationSite(town, stationRotation, destination))
			subtasks.append(BuildStopInTown(this, info.id, cargo));
		} else {
		}
	}

	function FindStationSites(a, b) {
		local locA = producer_info.loc;
		local locB = consumer_info.loc;
		
		local nameA = producer_info.name;
		local dirA = StationDirection(locA, locB);
		local rotA = BuildTerminusStation.StationRotationForDirection(dirA);
		local siteA;
		if (producer_info.type == AISubsidy.SPT_TOWN) {
			siteA = FindTransferStationSite(producer_info.loc,
				rotA, consumer_info.loc);
		} else {
			siteA = FindIndustryStationSite(a, true, rotA, locB);
		}

		local nameB = consumer_info.name;
		local dirB = StationDirection(locB, locA);
		local rotB = BuildTerminusStation.StationRotationForDirection(dirB);
		local siteB;
		if (consumer_info.type == AISubsidy.SPT_TOWN) {
			siteB = FindTransferStationSite(consumer_info.loc,
				rotB, producer_info.loc);
		} else {
			siteB = FindIndustryStationSite(b, false, rotB, locA);
		}
		
		if (siteA && siteB) {
			return [siteA, rotA, dirA, siteB, rotB, dirB];
		} else {
			Debug("Cannot build a station at " + (siteA ? nameB : nameA));
			return null;
		}
	}

	function FindTransferStationSite(location, stationRotation, destination) {
		local TRANSFER_RADIUS = 5;
		local area = AITileList();
		SafeAddRectangle(area, location, TRANSFER_RADIUS);
		
		// room for a station
		area.Valuate(IsBuildableRectangle, stationRotation, [0, -1], [1, CARGO_STATION_LENGTH + 1], true);
		area.KeepValue(1);
		
		// pick the tile farthest from the destination for increased profit
		area.Valuate(AITile.GetDistanceManhattanToTile, destination);
		area.KeepTop(1);
		
		// pick the tile closest to the industry for looks
		//area.Valuate(AITile.GetDistanceManhattanToTile, location);
		//area.KeepBottom(1);
		
		return area.IsEmpty() ? null : area.Begin();
	}
	
	/**
	 * Find a site for a station at the given industry.
	 */
	function FindIndustryStationSite(industry, producing, stationRotation, destination) {
		local location = AIIndustry.GetLocation(industry);
		local area = producing ? AITileList_IndustryProducing(industry, RAIL_STATION_RADIUS) : AITileList_IndustryAccepting(industry, RAIL_STATION_RADIUS);
		
		// room for a station
		area.Valuate(IsBuildableRectangle, stationRotation, [0, -1], [1, CARGO_STATION_LENGTH + 1], true);
		area.KeepValue(1);
		
		// pick the tile farthest from the destination for increased profit
		area.Valuate(AITile.GetDistanceManhattanToTile, destination);
		area.KeepTop(1);
		
		// pick the tile closest to the industry for looks
		//area.Valuate(AITile.GetDistanceManhattanToTile, location);
		//area.KeepBottom(1);
		
		return area.IsEmpty() ? null : area.Begin();
	}
}

