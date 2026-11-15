-- Single-block SHA-256 for journal edition tokens. A guildmate can forward a
-- published withdrawal without gaining the ability to withdraw an active card.
local GL = GrudgeLedger
local mod = 4294967296
local band, bxor
if bit then
    band, bxor = bit.band, bit.bxor
else
    -- Standalone Lua 5.1 has no bit library. The game supplies the native operators.
    local function combine(a,b,xor)
        local result, place = 0, 1
        a,b=a%mod,b%mod
        for i=1,32 do
            local x,y=a%2,b%2
            if xor and x~=y or not xor and x+y==2 then result=result+place end
            a,b,place=(a-x)/2,(b-y)/2,place*2
        end
        return result
    end
    band=function(a,b) return combine(a,b,false) end
    bxor=function(a,b) return combine(a,b,true) end
end
local function rotate(a,n) return math.floor(a/2^n)+(a%2^n)*2^(32-n) end
local function xor3(a,b,c) return bxor(bxor(a,b),c) end
local K={
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}
function GL.RevocationDigest(token)
    if type(token)~="string" or #token>55 or not token:match("^%x+$") then return end
    local bits=#token*8
    local block=token..string.char(128)..string.rep("\0",55-#token)
    local h={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
    local w={}
    for i=1,14 do
        local a,b,c,d=block:byte(4*i-3,4*i)
        w[i]=((a*256+b)*256+c)*256+d
    end
    w[15],w[16]=0,bits
    local a,b,c,d,e,f,g,v=unpack(h)
    for i=1,64 do
        if i>16 then
            local x,y=w[i-15],w[i-2]
            w[i]=(w[i-16]+xor3(rotate(x,7),rotate(x,18),math.floor(x/8))+w[i-7]+
                xor3(rotate(y,17),rotate(y,19),math.floor(y/1024)))%mod
        end
        local t=(v+xor3(rotate(e,6),rotate(e,11),rotate(e,25))+bxor(band(e,f),band(0xffffffff-e,g))+K[i]+w[i])%mod
        local u=(xor3(rotate(a,2),rotate(a,13),rotate(a,22))+xor3(band(a,b),band(a,c),band(b,c)))%mod
        a,b,c,d,e,f,g,v=(t+u)%mod,a,b,c,(d+t)%mod,e,f,g
    end
    local out={a,b,c,d,e,f,g,v}
    for i=1,8 do out[i]=("%08x"):format((out[i]+h[i])%mod) end
    return table.concat(out)
end
