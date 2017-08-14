const VEN = artifacts.require('./VEN.sol')
const Sale = artifacts.require('./MockedVENSale.sol')
const { assertFail, assertEqual } = require('./utils.js')
var crypto = require('crypto')

contract('Sale', accounts => {
  const ethValut = '0x' + crypto.randomBytes(20).toString('hex')
  const venVault = '0x' + crypto.randomBytes(20).toString('hex')

  const channel1Address = '0x' + crypto.randomBytes(20).toString('hex')

  const buyer1 = accounts[0]
  const buyer2 = accounts[1]
  const buyer3 = accounts[2]

  let ven
  let sale

  const totalSupply = web3.toWei(10 ** 9)
  const nonPubSupply = web3.toWei((10 ** 9) * 59 / 100)
  const pubSupply = web3.toWei((10 ** 9) * 41 / 100)  

  const Stage = {
    Created: 1,
    Initialized: 2,
    Early: 3,
    Normal: 4,
    Closed: 5,
    Finalized: 6
  }

  it('deploy', async () => {
    // activate vault to decrease gas usage
    await web3.eth.sendTransaction({ to: ethValut, value: 0, from: accounts[0] })
    ven = await VEN.new()
    sale = await Sale.new()
    // stage: created
    assertEqual(await sale.stage(), Stage.Created)

    // check constants   
    assertEqual(await sale.totalSupply(), totalSupply)

    assertEqual(await sale.nonPublicSupply(), nonPubSupply)
    assertEqual(await sale.publicSupply(), pubSupply)
  })

  const startTime = new Date("2017-08-18T12:00:00.000Z").getTime() / 1000
  const endTime = new Date("2017-08-31T12:00:00.000Z").getTime() / 1000
  const earlyStageLasts = 24 * 3600 * 3

  it('initialize', async () => {
    await ven.setOwner(sale.address)
    await sale.initialize(
      ven.address,
      ethValut,
      venVault)

    // stage: initialized
    assertEqual(await sale.stage(), Stage.Initialized)

    assertEqual(await sale.officialLimit(), web3.toWei(64371825))
    assertEqual((await sale.officialLimit()).add(await sale.channelsLimit()), pubSupply)

    // nonpublic supply minted after initialized
    assertEqual(await ven.totalSupply(), nonPubSupply)
    // to nonPubVenVault
    assertEqual(await ven.balanceOf(venVault), nonPubSupply)

    // check exchange rate
    assertEqual(await sale.exchangeRate(), 0)

    /// check params
    assertEqual(await sale.startTime(), startTime)
    assertEqual(await sale.endTime(), endTime)
    assertEqual(await sale.earlyStageLasts(), earlyStageLasts)
  })

  it('early stage', async () => {
    const exchangeRate = 4025

    await sale.setMockedBlockTime(startTime)
    // stage: early
    assertEqual(await sale.stage(), Stage.Early)
    await sale.setMockedBlockTime(startTime + earlyStageLasts - 1)
    assertEqual(await sale.stage(), Stage.Early)

    assertEqual(await sale.exchangeRate(), exchangeRate)

    const ethVaultBalance = web3.eth.getBalance(ethValut)
    const b1VenBalance = await ven.balanceOf(buyer1)

    // send 31 eth
    await sale.sendTransaction({ from: buyer1, value: web3.toWei(31) })

    // interval limit
    await assertFail(sale.sendTransaction({ from: buyer1, value: web3.toWei(1) }))

    // buyer should received ven based on 30 eth due to eth limit
    assertEqual(await ven.balanceOf(buyer1), b1VenBalance.add(web3.toWei(exchangeRate * 30)))

    // eth vault should received 30 eth
    assertEqual(web3.eth.getBalance(ethValut), ethVaultBalance.add(web3.toWei(30)))

    // small value should fail
    await assertFail(sale.sendTransaction({ from: buyer1, value: web3.toWei(0.001) }))
  })

  it('normal stage', async () => {
    const exchangeRate = 3500
    await sale.setMockedBlockTime(startTime + earlyStageLasts)
    // stage: normal
    assertEqual(await sale.stage(), Stage.Normal)
    await sale.setMockedBlockTime(endTime - 1)
    assertEqual(await sale.stage(), Stage.Normal)

    assertEqual(await sale.exchangeRate(), exchangeRate)

    const ethVaultBalance = web3.eth.getBalance(ethValut)
    const b2VenBalance = await ven.balanceOf(buyer2)
    // buy
    await sale.sendTransaction({ from: buyer2, value: web3.toWei(1) })

    // buyer should received ven
    assertEqual(await ven.balanceOf(buyer2), web3.toWei(exchangeRate))

    // eth vault should received another 1 eth
    assertEqual(web3.eth.getBalance(ethValut), ethVaultBalance.add(web3.toWei(1)))
  })

  it('offer to channels', async () => {
    const sold = await sale.channelsSold()
    const supply = await ven.totalSupply()

    const offer = 100

    await sale.offerToChannel(channel1Address, offer)

    assertEqual(await sale.channelsSold(), sold.add(offer))
    assertEqual(await ven.totalSupply(), supply.add(offer))
    assertEqual(await ven.balanceOf(channel1Address), offer)
  })

  it('closed stage', async () => {
    await sale.setMockedBlockTime(endTime)
    // stage: closed
    assertEqual(await sale.stage(), Stage.Closed)
    // buy should fail
    await assertFail(sale.sendTransaction({ from: buyer1, value: web3.toWei(1) }))
  })

  it('finalized stage', async () => {
    await sale.setMockedBlockTime(endTime - 1)
    // can't finalize before closed stage
    await assertFail(sale.finalize())

    await sale.setMockedBlockTime(endTime)
    await sale.finalize()
    // stage: finalized
    assertEqual(await sale.stage(), Stage.Finalized)

  })
})

