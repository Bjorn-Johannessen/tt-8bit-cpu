import cocotb
from cocotb.triggers import Timer

# Must match the localparams in src/alu.v
ALU_PASS, ALU_ADD, ALU_ADC, ALU_SUB = 0x0, 0x1, 0x2, 0x3
ALU_AND,  ALU_OR,  ALU_XOR =          0x4, 0x5, 0x6
ALU_SHL,  ALU_SHR, ALU_ROL, ALU_ROR = 0x8, 0x9, 0xA, 0xB
ALU_INC,  ALU_DEC, ALU_NOT, ALU_CLC = 0xC, 0xD, 0xE, 0xF


def alu_model(op, a, b, cin):
    """Return (result, c_out) as the ALU should compute them."""
    result = 0
    c_out = cin

    if (op == ALU_PASS):
        result = b

    elif (op == ALU_ADD):
        s = a + b
        result = s & 0xFF
        c_out = s >> 8

    elif (op == ALU_ADC):
        s = a + b + cin
        result = s & 0xFF
        c_out = s >> 8

    elif (op == ALU_SUB):
        s = a - b
        result = s & 0xFF
        c_out = 1 if (a < b) else 0

    elif (op == ALU_AND):
        result = a & b

    elif (op == ALU_OR):
        result = a | b

    elif (op == ALU_XOR):
        result = a ^ b

    elif (op == ALU_SHL):
        result = (a << 1) & 0xFF
        c_out = (a >> 7) & 1

    elif (op == ALU_SHR):
        result = (a >> 1) & 0xFF
        c_out = a & 1

    elif (op == ALU_ROL):
        result = ((a << 1) | cin) & 0xFF
        c_out = (a >> 7) & 1

    elif (op == ALU_ROR):
        result = ((a >> 1) | (cin << 7)) & 0xFF
        c_out = a & 1

    elif (op == ALU_INC):
        result = (a + 1) & 0xFF

    elif (op == ALU_DEC):
        result = (a - 1) & 0xFF

    elif (op == ALU_NOT):
        result = (~a) & 0xFF

    elif (op == ALU_CLC):
        result = a
        c_out = 0

    return result, c_out


@cocotb.test()
async def test_alu_exhaustive(dut):
    errors = 0
    checks = 0

    for op in range(16):
        # Unary ops (0x8-0xF) ignore b, so two b values are enough there
        b_values = range(256) if op < 8 else (0x00, 0xFF)

        for a in range(256):
            for b in b_values:
                for cin in (0, 1):
                    dut.op.value = op
                    dut.a.value = a
                    dut.b.value = b
                    dut.cin.value = cin
                    await Timer(1, unit="ns")   # let the logic settle

                    exp_result, exp_c = alu_model(op, a, b, cin)
                    exp_z = 1 if exp_result == 0 else 0

                    got_result = dut.result.value.to_unsigned()
                    got_z = int(dut.z.value)
                    got_c = int(dut.c_out.value)

                    checks += 1
                    if (got_result, got_z, got_c) != (exp_result, exp_z, exp_c):
                        errors += 1
                        if errors <= 10:   # don't flood the log
                            dut._log.error(
                                f"op={op:#x} a={a:#04x} b={b:#04x} cin={cin}: "
                                f"got result={got_result:#04x} z={got_z} c={got_c}, "
                                f"expected result={exp_result:#04x} z={exp_z} c={exp_c}"
                            )

    dut._log.info(f"{checks} checks, {errors} errors")
    assert errors == 0, f"{errors} mismatches"