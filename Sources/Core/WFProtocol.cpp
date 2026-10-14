// Framing and established command layouts adapted from SonyBridge (MIT).
// Copyright (c) 2020 Nir Harel, Mor Gal, Sem Visscher, jimzrt,
// guilhermealbm, and other contributors. See vendor/SonyBridge/LICENSE.
#include "WFProtocol.h"
#include <limits>
#include <algorithm>
#include <stdexcept>

namespace wf {
namespace {
constexpr uint8_t start = 0x3e, end = 0x3c, escape = 0x3d;
void putEscaped(Bytes& out, uint8_t byte) {
    if (byte >= end && byte <= start) { out.push_back(escape); out.push_back(byte - 0x10); }
    else out.push_back(byte);
}
uint32_t payloadSize(const Bytes& bytes) {
    return (uint32_t(bytes[2]) << 24) | (uint32_t(bytes[3]) << 16)
        | (uint32_t(bytes[4]) << 8) | uint32_t(bytes[5]);
}
uint8_t checksum(const Bytes& bytes, size_t count) {
    uint8_t result = 0;
    for (size_t i = 0; i < count; ++i) result = uint8_t(result + bytes[i]);
    return result;
}
std::optional<BatteryValue> battery(uint8_t level, uint8_t charging) {
    if (level == 0xff) return std::nullopt;
    // PowerBatteryChargingStatus.initialize 0x10140e258: 00 not charging,
    // 01 charging, 02 unknown, 03 charged. Do not confuse unknown with charging.
    return BatteryValue{int(level), charging == 1, charging == 0 || charging == 1 || charging == 3, charging == 3, charging};
}
uint8_t eqValue(int value) {
    if (value < -10 || value > 10) throw std::invalid_argument("EQ value must be -10...10");
    return uint8_t(value + 10);
}
} // namespace

Bytes encode(const Frame& frame, size_t maxPayload) {
    if (frame.payload.size() > maxPayload || frame.payload.size() > UINT32_MAX)
        throw std::length_error("Sony frame payload exceeds limit");
    const uint32_t size = uint32_t(frame.payload.size());
    Bytes raw{frame.type, frame.sequence, uint8_t(size >> 24), uint8_t(size >> 16), uint8_t(size >> 8), uint8_t(size)};
    raw.insert(raw.end(), frame.payload.begin(), frame.payload.end());
    raw.push_back(checksum(raw, raw.size()));
    Bytes result{start};
    result.reserve(2 * raw.size() + 2);
    for (auto byte : raw) putEscaped(result, byte);
    result.push_back(end);
    return result;
}

StreamDecoder::StreamDecoder(size_t maxPayload): maxPayload_(maxPayload) {
    if (maxPayload > UINT32_MAX || maxPayload > std::numeric_limits<size_t>::max() - 7)
        throw std::invalid_argument("Invalid frame payload limit");
}
void StreamDecoder::reset() { active_ = escaped_ = false; decoded_.clear(); rejected_ = 0; }
void StreamDecoder::reject() { ++rejected_; active_ = escaped_ = false; decoded_.clear(); }
std::vector<Frame> StreamDecoder::feed(const Bytes& input) {
    std::vector<Frame> result;
    for (uint8_t byte : input) {
        if (byte == start) {
            if (active_) reject();
            active_ = true; escaped_ = false; decoded_.clear();
            continue;
        }
        if (!active_) continue;
        if (byte == end) {
            if (escaped_ || decoded_.size() < 7 || payloadSize(decoded_) != decoded_.size() - 7
                || checksum(decoded_, decoded_.size() - 1) != decoded_.back()) {
                reject(); continue;
            }
            result.push_back({decoded_[0], decoded_[1], Bytes(decoded_.begin() + 6, decoded_.end() - 1)});
            active_ = false; decoded_.clear(); continue;
        }
        if (escaped_) {
            if (byte < 0x2c || byte > 0x2e) { reject(); continue; }
            decoded_.push_back(uint8_t(byte + 0x10)); escaped_ = false;
        } else if (byte == escape) { escaped_ = true; continue; }
        else decoded_.push_back(byte);
        if (decoded_.size() > maxPayload_ + 7
            || (decoded_.size() >= 6 && payloadSize(decoded_) > maxPayload_)) reject();
    }
    return result;
}

bool parseBattery(const Bytes& payload, uint8_t inquiry, BatteryLayout layout, BatteryState& state) {
    // IPA PowerRetStatusLeftRightBatteryBase accessors 0x10141820c...284:
    // inquiry=1, L%=2, Lcharging=3, R%=4, Rcharging=5. Cradle inherits
    // BatteryBase accessors 0x101416a20...68: inquiry=1, %=2, charging=3.
    const size_t count = layout == BatteryLayout::LeftRight ? 6 : 4;
    if (payload.size() != count || (payload[0] != 0x23 && payload[0] != 0x25) || payload[1] != inquiry) return false;
    for (size_t i = 2; i < count; i += 2)
        if ((payload[i] > 100 && payload[i] != 0xff) || (payload[i + 1] > 3 && payload[i + 1] != 0xff)) return false;
    if (layout == BatteryLayout::LeftRight) {
        state.left = battery(payload[2], payload[3]); state.right = battery(payload[4], payload[5]);
    } else if (layout == BatteryLayout::Case) state.caseBattery = battery(payload[2], payload[3]);
    else state.single = battery(payload[2], payload[3]);
    return true;
}

std::optional<AmbientCapabilities> parseAmbientCapabilities(const Bytes& payload) {
    // IPA list helper 0x1015fce94: count=2, records start=3, stride=4;
    // each record is ambientMode + Range(min,max,step). Range constructor
    // 0x1018310b0. Verified live firmware 2.3.1 response contains two modes.
    if (payload.size() < 3 || payload[0] != 0x61 || (payload[1] != kAmbientInquiry && payload[1] != 0x15)
        || payload[2] == 0 || payload.size() != size_t(3 + 4 * payload[2])) return std::nullopt;
    AmbientCapabilities result;
    std::array<bool, 256> seen{};
    for (size_t offset = 3; offset < payload.size(); offset += 4) {
        uint8_t mode = payload[offset];
        int minimum = payload[offset + 1], maximum = payload[offset + 2], step = payload[offset + 3];
        if (seen[mode] || minimum > maximum || step == 0) return std::nullopt;
        seen[mode] = true;
        result.ranges.push_back({mode, minimum, maximum, step});
    }
    return result;
}

std::optional<AmbientCapabilities> parseLegacyAmbientCapabilities(const Bytes& p) {
    // MIT libmdr ProtocolV1T1.hpp RetNcAsmCapability_NcAsmCapability:
    // 61 02 ncSettingType ncStep asmSettingType asmCount [asmId asmStep]*.
    // Asm is two bytes (id, step). Expose only the level-adjustment schema
    // supported by this writer, with normal mode required. No header-only
    // fallback or guessed ambient range is allowed.
    if(p.size()<8 || p[0]!=0x61 || p[1]!=2 || p[2]>2 || p[4]!=1 ||
       p[5]==0 || p[5]>2 || p.size()!=size_t(6+2*p[5])) return std::nullopt;
    AmbientCapabilities result; std::array<bool,2> seen{};
    for(size_t offset=6;offset<p.size();offset+=2) {
        const uint8_t mode=p[offset], step=p[offset+1];
        if(mode>1 || seen[mode] || step==0 || step>20) return std::nullopt;
        seen[mode]=true;
        result.ranges.push_back({mode,1,step,1});
    }
    if(!seen[0]) return std::nullopt;
    return result;
}

std::optional<AmbientState> parseAmbient(const Bytes& payload) {
    // IPA NcAsmInquiredTypeV2 dual-mode switch wire code=17 (ordinal=07).
    // WF-1000XM4 advertises AUTO_NC inquiry15: observed response
    // 67 15 01 00 00 02 01 10. IPA helper0x10160362c...914 establishes
    // mode4, NCvalue5, ambientMode6, level7. Preserve NC value when editing.
    // Base accessors
    // 0x10161005c/134: changeStatus=2, totalEffect=3; helpers
    // 0x101605db4/eac/fa4: mode=4, ambientMode=5, level=6.
    if (payload.size()<7 || (payload[0] != 0x67 && payload[0] != 0x69)) return std::nullopt;
    const bool autoNC=payload[1]==0x15;
    if ((autoNC && (payload.size()!=8 || payload[5]>5)) ||
        (!autoNC && (payload.size()!=7 || payload[1]!=kAmbientInquiry)) ||
        payload[2]>1 || payload[3]>1 || payload[4]>1 || payload[autoNC?6:5]>1) return std::nullopt;
    auto mode = !payload[3] ? AmbientMode::Off : payload[4] ? AmbientMode::Ambient : AmbientMode::NoiseCancelling;
    return AmbientState{mode, payload[autoNC?6:5] != 0, payload[autoNC?7:6], payload[2] == 1,
                        payload[1], autoNC?payload[5]:uint8_t(2)};
}
Bytes setAmbient(const AmbientState& state) {
    if(state.inquiry==2) {
        if(state.level<1 || state.level>20) throw std::invalid_argument("Legacy ambient level must be 1...20");
        return {0x68,2,uint8_t(state.mode==AmbientMode::Off?0:0x11),1,
            uint8_t(state.mode==AmbientMode::NoiseCancelling?2:0),1,uint8_t(state.focusOnVoice),
            uint8_t(state.mode==AmbientMode::Ambient?state.level:0)};
    }
    if (state.level < 1 || state.level > 255) throw std::invalid_argument("Ambient level must be 1...255");
    if(state.inquiry!=0x15 && state.inquiry!=kAmbientInquiry) throw std::invalid_argument("Unsupported ANC profile");
    Bytes command{0x68, state.inquiry, 0x01, uint8_t(state.mode != AmbientMode::Off),
                  uint8_t(state.mode == AmbientMode::Ambient)};
    if(state.inquiry==0x15) {
        if(state.ncValue>5) throw std::invalid_argument("Invalid NC value");
        command.push_back(state.ncValue);
    }
    command.push_back(uint8_t(state.focusOnVoice)); command.push_back(uint8_t(state.level));
    return command;
}
std::optional<AmbientState> parseLegacyAmbient(const Bytes& p) {
    // MIT libmdr V1T1 RetNcAsmParamNcAsmParam: effect, ncType,ncValue,
    // asmType,asmId,asmValue; dual NC2, single NC1, ambient value1...20.
    if(p.size()!=8 || (p[0]!=0x67 && p[0]!=0x69) || p[1]!=2 ||
       (p[2]!=0 && p[2]!=1 && p[2]!=0x10 && p[2]!=0x11) || p[4]>2 || p[6]>1 || p[7]>20) return std::nullopt;
    AmbientMode mode=p[2]==0?AmbientMode::Off:p[4]>0?AmbientMode::NoiseCancelling:AmbientMode::Ambient;
    return AmbientState{mode,p[6]!=0,p[7]?p[7]:1,p[2]!=0x10,2,p[4]};
}

std::optional<EQCapabilities> parseEQCapabilities(const Bytes& payload) {
    // Verified WF-1000XM4 firmware 2.3.1 capture: 51 00 06 15 0c ...
    // Header holds band count, step count, preset count. Each preset carries
    // an id and byte-length-prefixed name (all names empty in this capture).
    if (payload.size() < 5 || payload.size() > kMaxPayload || payload[0] != 0x51
        || payload[1] != 0 || payload[2] == 0 || payload[3] == 0 || payload[4] == 0) return std::nullopt;
    EQCapabilities result{payload[2], payload[3], {}};
    size_t offset = 5;
    std::array<bool, 256> seen{};
    for (unsigned i = 0; i < payload[4]; ++i) {
        if (offset + 2 > payload.size()) return std::nullopt;
        auto id = payload[offset++]; auto length = payload[offset++];
        if (seen[id] || length > payload.size() - offset) return std::nullopt;
        seen[id] = true;
        result.presets.push_back({id, std::string(payload.begin() + offset, payload.begin() + offset + length)});
        offset += length;
    }
    if (offset != payload.size()) return std::nullopt;
    return result;
}

std::optional<EQState> parseEQ(const Bytes& payload) {
    if (payload.size() < 4 || (payload[0] != 0x57 && payload[0] != 0x59)
        || payload[1] != 0 || payload.size() != size_t(4 + payload[3])) return std::nullopt;
    EQState state; state.preset = payload[2];
    if (payload[3] == 6) {
        for (size_t i = 4; i < 10; ++i) if (payload[i] > 20) return std::nullopt;
        state.clearBass = int(payload[4]) - 10;
        std::array<int, 5> bands{};
        for (size_t i = 0; i < 5; ++i) bands[i] = int(payload[5 + i]) - 10;
        state.bands = bands;
    } else if (payload[3] != 0) return std::nullopt;
    return state;
}
Bytes setEQPreset(uint8_t preset) { return {0x58, 0, preset, 0}; }
Bytes setEQCustom(int clearBass, const std::array<int, 5>& bands) {
    Bytes result{0x58, 0, 0xa0, 6, eqValue(clearBass)};
    for (auto value : bands) result.push_back(eqValue(value));
    return result;
}

Frame CommandTracker::begin(const Bytes& payload, std::optional<uint8_t> opcode,
                            std::optional<uint8_t> inquiry, uint64_t nowMs, uint64_t timeoutMs, uint8_t dataType) {
    if (status_ == TransactionStatus::Waiting) throw std::logic_error("Command already in flight");
    if (timeoutMs == 0 || nowMs > UINT64_MAX - timeoutMs) throw std::invalid_argument("Invalid timeout");
    if (!opcode && inquiry) throw std::invalid_argument("Response inquiry requires opcode");
    if(dataType!=kData && dataType!=0x0e) throw std::invalid_argument("Unsupported Sony data table");
    pending_ = {dataType, nextSequence_, payload};
    opcode_ = opcode; inquiry_ = inquiry; response_.reset(); acknowledged_ = false;
    deadline_ = nowMs + timeoutMs; status_ = TransactionStatus::Waiting;
    return pending_;
}
void CommandTracker::updateStatus() {
    if (acknowledged_ && (!opcode_ || response_)) status_ = TransactionStatus::Complete;
}
bool CommandTracker::observe(const Frame& frame) {
    if (status_ != TransactionStatus::Waiting) return false;
    if (frame.type == kAck && frame.payload.empty() && frame.sequence == uint8_t(1 - pending_.sequence)) {
        if (acknowledged_) return false;
        acknowledged_ = true; nextSequence_ = frame.sequence; updateStatus(); return true;
    }
    if (frame.type == pending_.type && opcode_ && !frame.payload.empty() && frame.payload[0] == *opcode_
        && (!inquiry_ || (frame.payload.size() >= 2 && frame.payload[1] == *inquiry_))) {
        if (response_) return false;
        response_ = frame.payload; updateStatus(); return true;
    }
    return false;
}
bool CommandTracker::expire(uint64_t nowMs) {
    if (status_ == TransactionStatus::Waiting && nowMs >= deadline_) { status_ = TransactionStatus::TimedOut; return true; }
    return false;
}
void CommandTracker::reset() {
    pending_ = {}; nextSequence_ = 0; deadline_ = 0; status_ = TransactionStatus::Idle;
    acknowledged_ = false; opcode_.reset(); inquiry_.reset(); response_.reset();
}
ReceiveResult ReceiveWindow::observe(const Frame& frame) {
    if ((frame.type != kData && frame.type != 0x0e) || frame.sequence > 1) return {};
    bool duplicate = previous_ && previous_->type == frame.type && previous_->sequence == frame.sequence
        && previous_->payload == frame.payload;
    previous_ = frame;
    return {Frame{kAck, uint8_t(1 - frame.sequence), {}}, !duplicate};
}
std::optional<ProtocolInfo> parseProtocolInfo(const Bytes& p, ProtocolFamily family) {
    if(p.size()<2 || p[0]!=1 || p[1]!=0) return std::nullopt;
    if(family==ProtocolFamily::V1) {
        if(p.size()!=4) return std::nullopt;
        return ProtocolInfo{uint32_t(p[2])<<8 | p[3],true,false};
    }
    // libmdr ConnectRetProtocolInfo: Int32BE at2, EnableDisable flags6,7.
    // ENABLE=00, DISABLE=01. These are not protocol-version components.
    if(p.size()!=8 || p[6]>1 || p[7]>1) return std::nullopt;
    return ProtocolInfo{uint32_t(p[2])<<24 | uint32_t(p[3])<<16 | uint32_t(p[4])<<8 | p[5],p[6]==0,p[7]==0};
}
std::optional<std::vector<uint8_t>> parseSupportFunctions(const Bytes& p, ProtocolFamily family) {
    const size_t stride=family==ProtocolFamily::V2?2:1;
    if(p.size()<3 || p[0]!=7 || p[1]!=0 || p.size()!=3+stride*p[2]) return std::nullopt;
    std::vector<uint8_t> result;
    for(size_t i=3;i<p.size();i+=stride) result.push_back(p[i]);
    return result;
}
std::vector<SettingSpec> settingSpecs(ProtocolFamily family, const std::vector<uint8_t>& functions) {
    // Layouts and function tags cross-checked with MIT libmdr ProtocolV1T1,
    // ProtocolV2T1 at pinned f11d686332e9aaf7630f9fb8a104b70c5d6f342c.
    const bool v2=family==ProtocolFamily::V2;
    std::vector<SettingSpec> candidates;
    auto add=[&](std::string id,std::string title,std::string section,uint8_t function,uint8_t inquiry,
        uint8_t get,uint8_t ret,uint8_t set,size_t size,size_t offset,std::vector<SettingOption> options,bool inverted=false,bool caps=false){
        candidates.push_back({id,title,section,function,inquiry,get,ret,set,size,offset,options,inverted,caps});
    };
    add("soundQuality","Connection quality","Audio",0xe1,v2?0:1,0xe6,0xe7,0xe8,v2?3:4,v2?2:3,{{0,"Prioritize sound quality"},{1,"Prioritize stable connection"}});
    add("dsee","DSEE","Audio",0xe2,v2?1:2,0xe6,0xe7,0xe8,v2?3:4,v2?2:3,{{0,"Off"},{1,"Auto"}});
    add("wearPause","Pause when removed","System",v2?0xf1:0xf3,v2?1:3,0xf6,0xf7,0xf8,v2?3:4,v2?2:3,{{0,"Off"},{1,"On"}},v2);
    add("speakToChat","Speak to Chat","System",v2?0xfc:0xf5,v2?0x0c:5,0xf6,0xf7,0xf8,4,v2?2:3,{{0,"Off"},{1,"On"}},v2);
    if(v2) {
        add("speakToChatLegacy","Speak to Chat","System",0xf2,2,0xf6,0xf7,0xf8,4,2,{{0,"Off"},{1,"On"}},true);
        add("speakSensitivityLegacy","Speak to Chat sensitivity","System",0xf2,2,0xfa,0xfb,0xfc,5,2,{{0,"Auto"},{1,"High"},{2,"Low"}});
        add("speakVoiceFocus","Speak to Chat voice focus","System",0xf2,2,0xfa,0xfb,0xfc,5,3,{{0,"Off"},{1,"On"}},true);
        add("speakTimeoutLegacy","Speak to Chat resume time","System",0xf2,2,0xfa,0xfb,0xfc,5,4,{{0,"Fast"},{1,"Medium"},{2,"Slow"},{3,"Do not resume automatically"}});
        add("autoOff","Automatic power off","Power",0x25,5,0x26,0x27,0x28,4,2,{{0,"After 5 minutes"},{1,"After 30 minutes"},{2,"After 1 hour"},{3,"After 3 hours"},{4,"After 15 minutes"},{0x10,"When removed"},{0x11,"Never"}},false,true);
        add("autoOffTimer","Automatic power off","Power",0x24,4,0x26,0x27,0x28,4,2,{{0,"After 5 minutes"},{1,"After 30 minutes"},{2,"After 1 hour"},{3,"After 3 hours"},{4,"After 15 minutes"},{0x11,"Never"}},false,true);
        add("speakSensitivity","Speak to Chat sensitivity","System",0xfc,0x0c,0xfa,0xfb,0xfc,4,2,{{0,"Auto"},{1,"High"},{2,"Low"}});
        add("speakTimeout","Speak to Chat resume time","System",0xfc,0x0c,0xfa,0xfb,0xfc,4,3,{{0,"Fast"},{1,"Medium"},{2,"Slow"},{3,"Do not resume automatically"}});
        add("headGesture","Head gestures","System",0xff,0x0f,0xf6,0xf7,0xf8,3,2,{{0,"Off"},{1,"On"}},true);
        add("vibrator","Vibration","System",0xf0,0,0xf6,0xf7,0xf8,3,2,{{0,"Off"},{1,"On"}},true);
        add("autoVolume","Adaptive volume","Audio",0xfa,0x0a,0xf6,0xf7,0xf8,3,2,{{0,"Off"},{1,"On"}},true);
    } else {
        add("autoOff","Automatic power off","Power",0xf4,4,0xf6,0xf7,0xf8,5,3,{{0,"After 5 minutes"},{1,"After 30 minutes"},{2,"After 1 hour"},{3,"After 3 hours"},{0x10,"When removed"},{0x11,"Never"}},false,true);
    }
    std::vector<SettingSpec> result;
    for(auto& spec:candidates) if(std::find(functions.begin(),functions.end(),spec.function)!=functions.end()) result.push_back(spec);
    return result;
}
std::optional<std::vector<AssignmentKey>> parseAssignmentCapabilities(const Bytes& p) {
    if(p.size()<3 || p[0]!=0xf1 || p[1]!=3 || p[2]==0) return std::nullopt;
    size_t offset=3; std::vector<AssignmentKey> result;
    auto take=[&](size_t n){ if(n>p.size()-offset) throw std::out_of_range("Truncated assignment capability"); size_t old=offset; offset+=n; return old; };
    try {
        for(unsigned keyIndex=0;keyIndex<p[2];++keyIndex) {
            auto header=take(4); AssignmentKey key{p[header],p[header+1],p[header+2],{}};
            if(key.key>5 || key.type>2 || p[header+3]==0 || std::any_of(result.begin(),result.end(),[&](const auto& prior){return prior.key==key.key;})) return std::nullopt;
            for(unsigned presetIndex=0;presetIndex<p[header+3];++presetIndex) {
                auto preset=take(3); key.presets.push_back(p[preset]);
                take(size_t(p[preset+1])*2);
                for(unsigned action=0;action<p[preset+2];++action) { auto actionHeader=take(3); take(p[actionHeader+2]); }
            }
            result.push_back(key);
        }
    } catch(const std::out_of_range&) { return std::nullopt; }
    if(offset!=p.size()) return std::nullopt;
    return result;
}
std::optional<std::vector<uint8_t>> parseAssignmentValues(const std::vector<AssignmentKey>& keys,const Bytes& p) {
    if(keys.empty() || keys.size()>255 || p.size()!=3+keys.size() || p[0]!=0xf7 || p[1]!=3 || p[2]!=keys.size()) return std::nullopt;
    std::vector<uint8_t> values(p.begin()+3,p.end());
    for(size_t i=0;i<keys.size();++i)
        if(std::find(keys[i].presets.begin(),keys[i].presets.end(),values[i])==keys[i].presets.end()) return std::nullopt;
    return values;
}
std::optional<std::vector<bool>> parseAssignmentAvailability(size_t count,const Bytes& p) {
    if(!count || count>255 || p.size()!=3+count || p[0]!=0xf3 || p[1]!=3 || p[2]!=count) return std::nullopt;
    std::vector<bool> enabled;
    for(size_t i=3;i<p.size();++i) { if(p[i]>1) return std::nullopt; enabled.push_back(p[i]==0); }
    return enabled;
}
Bytes setAssignmentValues(const std::vector<AssignmentKey>& keys,const Bytes& current,const std::vector<std::optional<uint8_t>>& changes) {
    if(!parseAssignmentValues(keys,current) || changes.size()!=keys.size()) throw std::invalid_argument("Invalid current touch-control list.");
    Bytes command=current; command[0]=0xf8;
    for(size_t i=0;i<changes.size();++i) if(changes[i]) {
        if(std::find(keys[i].presets.begin(),keys[i].presets.end(),*changes[i])==keys[i].presets.end()) throw std::invalid_argument("Touch action is not advertised by the headphones.");
        command[i+3]=*changes[i];
    }
    return command;
}
std::optional<std::vector<PairedDevice>> parsePairedDevices(const Bytes& p) {
    if(p.size()<4 || p[0]!=0x37 || (p[1]!=0 && p[1]!=2)) return std::nullopt;
    size_t offset=3; std::vector<PairedDevice> result;
    for(unsigned i=0;i<p[2];++i) {
        if(p.size()-offset<19) return std::nullopt;
        std::string address(p.begin()+offset,p.begin()+offset+17); offset+=17;
        uint8_t status=p[offset++];
        if(p[1]==2) { if(p.size()-offset<3) return std::nullopt; offset+=3; }
        if(offset>=p.size()) return std::nullopt;
        size_t count=p[offset++]; if(count>p.size()-offset) return std::nullopt;
        std::string name(p.begin()+offset,p.begin()+offset+count); offset+=count;
        result.push_back({address,name,status});
    }
    if(p.size()-offset!=1 || (p.back()!=0xff && p.back()>p[2])) return std::nullopt;
    return result;
}
std::optional<SettingSpec> parseGeneralCapability(const Bytes& p) {
    if(p.size()<6 || p[0]!=0xd1 || p[1]<0xd1 || p[1]>0xd4 || p[2]>1 || p[3]>1) return std::nullopt;
    size_t offset=4;
    auto string=[&]()->std::string{ if(offset>=p.size()) throw std::out_of_range("General capability"); size_t count=p[offset++];if(count>p.size()-offset) throw std::out_of_range("General capability");std::string value(p.begin()+offset,p.begin()+offset+count);offset+=count;return value;};
    try {
        auto title=string(); auto description=string();
        if(title=="MULTIPOINT_SETTING") title="Connect to two devices simultaneously";
        SettingSpec spec{"general"+std::to_string(p[1]),title.empty()?"General headphone setting":title,"System",p[1],p[1],0xd6,0xd7,0xd8,4,3,{},p[2]==0,false};
        if(p[2]==0) spec.options={{0,"Off"},{1,"On"}};
        else {
            if(offset>=p.size()) return std::nullopt;
            unsigned count=p[offset++];if(count>64) return std::nullopt;
            for(unsigned i=0;i<count;++i) {if(offset>=p.size() || p[offset++]>1) return std::nullopt;auto label=string();string();spec.options.push_back({int(i),label.empty()?"Option "+std::to_string(i):label});}
        }
        if(offset!=p.size() || spec.options.empty()) return std::nullopt;
        return spec;
    }catch(const std::out_of_range&){return std::nullopt;}
}
std::optional<int> settingValue(const SettingSpec& spec,const Bytes& p) {
    if(p.size()<2 || p.size()!=spec.responseSize || p[0]!=spec.reply || p[1]!=spec.inquiry || spec.valueOffset>=p.size()) return std::nullopt;
    if(spec.get==0xd6 && (p.size()<4 || p[2]!=(spec.inverted?0:1))) return std::nullopt;
    int value=p[spec.valueOffset];
    if(spec.inverted) { if(value>1) return std::nullopt; value=1-value; }
    for(const auto& option:spec.options) if(option.value==value) return value;
    return std::nullopt;
}
Bytes settingCommand(const SettingSpec& spec,const Bytes& current,int selected) {
    if(!settingValue(spec,current)) throw std::invalid_argument("No valid current setting response");
    bool allowed=false; for(auto& option:spec.options) if(option.value==selected) allowed=true;
    if(!allowed) throw std::invalid_argument("Setting option not advertised");
    Bytes command=current; command[0]=spec.set; command[spec.valueOffset]=uint8_t(spec.inverted?1-selected:selected);
    // Smart Talking TYPE2 preview mode must remain off (wire01).
    if((spec.id=="speakToChat" || spec.id=="speakToChatLegacy") && spec.valueOffset==2) {
        if(command.size()<4) throw std::invalid_argument("Invalid Speak to Chat descriptor");
        command[3]=1;
    }
    if(spec.id=="voiceGuidance" && command.size()==4) command.resize(3);
    if(spec.id=="guidanceVolume") command.push_back(1); // feedback off
    return command;
}
} // namespace wf
