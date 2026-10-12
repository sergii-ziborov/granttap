import Foundation
import XCTest
@testable import GrantTap

final class AccountRecoveryNodeInteropTests: XCTestCase {
    func testNodeRecoveryOfferOpensOnIOS() throws {
        let encrypted = #"{"senderPublicKey":"XFtCMpyO2AH3qp8WvVUFQoz6in2XCtCL6C8Ol5M8Fgk=","nonce":"ufccQU78rTFa1/mDZPntF9eOp+B6egT/","box":"Vk8H/DH3bZG4vk3d0SVJMLWo5yrInVLLF0SQvHmZd/etNTDaUbUIp0B+O84nY+IdG/F4X9+h2LD6LuDY8Imyi9w2njh29yvAU5DhcclJRl2oNgYlmTIMY3+xsE4l9Fwra6OhoEY0UPzUDSp4GSs0AUjCXRmgKxtNk7BRg+mMbDSWPuRnZJp/7IvM6wpTJt6HJCSjzwzU+7VY731nC1+eCYjIxryOTSPtX+H4qEL/IQaEDzlCmXduJ+Dxo+csJBaOQO017L/bYzTV87gikUbKVl3fC9UA9MUrvIFCulXSLbTaUCBUagPDIv4X88bLRqbd/VwHBWoxkH4FDyOWEXzGBo9VmUHfujGAr+JrjV/gvcU8EQfJczMWUxxRyqhSLbiY5/y6BjDBplmKGrg5p6vjx6zbqGjXvmSI6fvQdOBd3luUML1p8su6t2vqad0FRqesnXMZ2gzKCFeXasJL392ZkxLMEzcu46UpdrsZGO5/V8ljduQDK/LG/qi47XnHMujdaQ4gAQ7hyid+0c0l4jd3Tr/SgDjyYo2op/Ka5rTiZqXc2M+Ior5sjtZCNP9IhVhxwVczCChaNbMJPwnBk0Jks914TJ3hHAnDfbb5FAokcrYLAUMVc4TjkJaLYE8O2820r9a6TjlKZ/z+XgsDYmF9HZyjujxnCjGai2LooB/vpucpEJ2T9Zjzxp23+3Zi7bX9XYSKFa2wwhO5u+3oZHfqO8DBfqAbxbAZAQiiGHHK7xVi03QDLZuyz+A="}"#
        let secret = try XCTUnwrap(Data(base64Encoded: "kAJwCMaYTKNntdRMYcMD9zaPLkKe/7vt4o0HMv4uLJk="))
        let pairing = try AccountRecovery.open(encrypted,
            requestId: "11111111-1111-4111-8111-111111111111", machineId: "22222222-2222-4222-8222-222222222222", secretKey: secret)
        XCTAssertEqual(pairing.room, "eb8097cd3cd7f941b47b3edbf685b362")
        XCTAssertEqual(pairing.role, "phone")
    }
}
