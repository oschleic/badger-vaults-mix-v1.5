import brownie
from brownie import *
from brownie import (
    interface,
    accounts
)
from helpers.constants import MaxUint256
from helpers.SnapshotManager import SnapshotManager
from helpers.time import days

"""
  TODO: Put your tests here to prove the strat is good!
  See test_harvest_flow, for the basic tests
  See test_strategy_permissions, for tests at the permissions level
"""

def test_does_it_claim_fees(deployer, vault, strategy, want, governance, feedist, randomUser):
    depositAmount = int(want.balanceOf(deployer) * 0.8)

    want.approve(vault, MaxUint256, {"from": deployer})
    vault.deposit(depositAmount, {"from": deployer})

    vault.earn({"from": governance})
  
    chain.sleep(100000) #Sleep to earn
    chain.mine(1)

    #Deposit as fees to the fee distrbutor
    wftmDepositAmount = (interface.IERC20Detailed("0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83").balanceOf(randomUser) * 0.8)
    feedist.depositFee("0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83", wftmDepositAmount, {"from": randomUser})

    harvest = strategy.harvest({"from": governance})
    print(harvest.events["TestEvent"])

    chain.sleep(604800 * 2 + 2)  # 2 weeks
    chain.mine(1)

    harvest = strategy.harvest({"from": governance})

    event = harvest.events["TreeDistribution"]
    print(harvest.events["TestEvent"])
    assert event["token"] == "0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83" ## wftm token
    assert event["amount"] > 0 ## We want it to emit something
    assert event["amount"] < wftmDepositAmount ## We shouldn't get all of the fees back

    harvest = strategy.harvest({"from": governance})
    event = harvest.events["TreeDistribution"]

    assert event["token"] == "0xD31Fcd1f7Ba190dBc75354046F6024A9b86014d7" ## sex token should be withdrawn from the stream
    assert event["amount"] > 0 ## We want it to emit something
    assert False
