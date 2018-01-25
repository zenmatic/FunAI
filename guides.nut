
class GuidingStrategy {
	desc = "base guiding strategy";
	strategies = [];
	condition = false;

	// condition must return true to activate this guiding strategy
	function Condition() {
		return false;
	}

	function DoAction(action, arg=null) {
		local ret = Condition();
		Debug("Condition returned ", ret);
		if (ret == false) { return }

		local strat;
		Debug("number of strategies are ", strategies.len());
		foreach (strat in strategies) {
			Debug("strategy: action ", action, " on ", strat.desc);
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
				} else if (action == "Event") {
					strat.Event(arg);
					strat.RunTasks();
				}
			} catch (e) {
				Error("exception thrown");
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
	function Event(e) {
		DoAction("Event", e);
	}
}

class VerySmallMapGuide extends GuidingStrategy {
	desc = "strategies for 64x64 maps";

	constructor() {
		strategies = [
			MaxLoanStrategy(),
			SimpleSuppliesStrategy(),
			//BusesToPopularTowns(1),
			//SubStrategy(),
			ZeroLoanStrategy(),
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

		// a year later, add subsidies
		// a year later, add simple routes

		GuidingStrategy.Wake();
	}
}

// other ideas:
// very urban maps
// lots of water
// long maps (like 64x512)
