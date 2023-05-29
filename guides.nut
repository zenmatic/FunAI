
class GuidingStrategy {
	static desc = "base guiding strategy";
	strategies = [];
	condition = false;

	// condition must return true to activate this guiding strategy
	function Condition() {
		return condition;
	}

	function DoAction(action, arg=null) {
		local ret = Condition();
		if (ret == false) { return }

		local strat;
		//Debug("number of strategies are ", strategies.len());
		foreach (strat in strategies) {
			//Debug("strategy: action ", action, " on ", strat.desc);
			try {
				if (action == "Start") {
					strat.Start();
					strat.RunTasks();
				} else if (action == "Stop") {
					strat.Stop();
				} else if (action == "Uninit") {
					strat.Uninit();
				} else if (action == "Wake") {
					strat.Wake();
					strat.RunTasks();
				} else if (action == "Quarterly") {
					strat.Quarterly();
					strat.RunTasks();
				} else if (action == "Event") {
					strat.Event(arg);
					strat.RunTasks();
				}
			} catch (e) {
				Error("exception thrown:", e);
			}
		}
	}
	function Start() {
		DoAction("Start");
	}
	function Stop() {
		DoAction("Stop");
	}
	function Uninit() {
		DoAction("Uninit");
	}
	function Wake() {
		DoAction("Wake");
	}
	function Quarterly() {
		DoAction("Quarterly");
	}
	function Event(e) {
		DoAction("Event", e);
	}
}

class VerySmallMapGuide extends GuidingStrategy {
	desc = "strategies for 64x64 maps";

	constructor() {
		//local cargos = GenCargos();
		//local fruit = cargos.GRAI;
		strategies = [
			//ExpandTowns(1, 1000, 30),
			BusesToPopularTowns(1),
			SubStrategy(),
			/*  COMMENTED OUT
			SimpleSuppliesStrategy({
				maxroutes = 10,
				delay = 365,
				interval = 365,
				mindistance = 5,
				maxdistance = 30,
			}),
			AuxSuppliesStrategy({
				maxroutes = 5,
				delay = 730,
				interval = 100,
				mindistance = 5,
				maxdistance = 30,
			}),
			*/
		];
	}

	function Condition() {
		local x = AIMap.GetMapSizeX();
		local y = AIMap.GetMapSizeY();
		if (x == 64 && y == 64) {
			return true;
		}
		return false;
	}

	function Wake() {

		local m = MaxLoanStrategy();
		m.Start();
		GuidingStrategy.Wake();
		local z = ZeroLoanStrategy();
		z.Start();
	}
}

class BigCityRoutes extends GuidingStrategy {
	desc = "build routes in the largest city";
	townID = null;

	constructor(minpopulation=7000) {

		townID = null;
		local towns = AITownList();
		towns.Valuate(AITown.GetPopulation);
		towns.KeepAboveValue(minpopulation);
		towns.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		if (towns.IsEmpty()) { return }
		townID = towns.Begin();
		local name = AITown.GetName(townID);
		local pop = AITown.GetPopulation(townID);
		Debug("biggest town is ", name, "with a population of ", pop);

		strategies = [
			LocalTownStations(townID),
		];
	}

	function Condition() {
		if (this.townID != null) {
			return true;
		}
		return false;
	}

	function Wake() {

		local m = MaxLoanStrategy();
		m.Start();
		GuidingStrategy.Wake();
		local z = ZeroLoanStrategy();
		z.Start();
	}
}

// other ideas:
// very urban maps
// lots of water
// long maps (like 64x512)
