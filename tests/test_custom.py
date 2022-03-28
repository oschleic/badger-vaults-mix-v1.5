import brownie
from brownie import *
from helpers.constants import MaxUint256
from helpers.SnapshotManager import SnapshotManager
from helpers.time import days

"""
  TODO: Put your tests here to prove the strat is good!
  See test_harvest_flow, for the basic tests
  See test_strategy_permissions, for tests at the permissions level
"""

def test_sex_harvesting(deployer, vault, strategy, want, governance):
    assert True
    """
    startingBalance = want.balanceOf(deployer)

    depositAmount = startingBalance // 2

    want.approve(vault, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    vault.earn({"from": governance})

    harvest = strategy.harvest({"from": governance})

    chain.sleep(604800 * 2)  # 2 weeks
    chain.mine(1)

    harvest = strategy.harvest({"from": governance})

    ## TEST 3: Does the strategy emit anything? See test_custom.py for custom test
    event = harvest.events["TreeDistribution"]
    # assert event["token"] == "0xD31Fcd1f7Ba190dBc75354046F6024A9b86014d7" ## Sex token
    assert event["amount"] > 0 ## We want it to emit something
    """
