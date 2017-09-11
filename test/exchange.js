const MockedExchange = artifacts.require('./MockedExchange.sol')
const VEN = artifacts.require('./VEN.sol')


const { assertFail, assertEqual } = require('./utils.js')
var crypto = require('crypto')

contract('Exchange', accounts => {
    const acc1 = accounts[0]
    const acc2 = accounts[1]
    const acc3 = accounts[2]
    const acc4 = accounts[3]

    let exchange
    let ven

    it('deploy', async() => {

    })

})

