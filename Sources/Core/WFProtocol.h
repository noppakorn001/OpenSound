// Framing and established command layouts adapted from SonyBridge (MIT).
// Copyright (c) 2020 Nir Harel, Mor Gal, Sem Visscher, jimzrt,
// guilhermealbm, and other contributors. See vendor/SonyBridge/LICENSE.
#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace wf {
enum class ProtocolFamily { V1, V2 };
struct ProtocolInfo { uint32_t version; bool table1, table2; };
std::optional<ProtocolInfo> parseProtocolInfo(const std::vector<uint8_t>&, ProtocolFamily);
struct SettingOption { int value; std::string label; };
struct SettingSpec {
    std::string id, title, section;
    uint8_t function, inquiry, get, reply, set;
    size_t responseSize, valueOffset;
    std::vector<SettingOption> options;
    bool inverted = false;
    bool capabilityOptions = false;
    int table = 1;
};
std::optional<std::vector<uint8_t>> parseSupportFunctions(const std::vector<uint8_t>&, ProtocolFamily);
struct AssignmentKey { uint8_t key, type, defaultPreset; std::vector<uint8_t> presets; };
std::optional<std::vector<AssignmentKey>> parseAssignmentCapabilities(const std::vector<uint8_t>&);
std::optional<std::vector<uint8_t>> parseAssignmentValues(const std::vector<AssignmentKey>&, const std::vector<uint8_t>&);
std::optional<std::vector<bool>> parseAssignmentAvailability(size_t keyCount, const std::vector<uint8_t>&);
std::vector<uint8_t> setAssignmentValues(const std::vector<AssignmentKey>&, const std::vector<uint8_t>& current,
    const std::vector<std::optional<uint8_t>>& changes);
struct PairedDevice { std::string address, name; uint8_t status; };
std::optional<SettingSpec> parseGeneralCapability(const std::vector<uint8_t>&);
std::optional<std::vector<PairedDevice>> parsePairedDevices(const std::vector<uint8_t>&);
std::vector<SettingSpec> settingSpecs(ProtocolFamily, const std::vector<uint8_t>& functions);
std::optional<int> settingValue(const SettingSpec&, const std::vector<uint8_t>&);
std::vector<uint8_t> settingCommand(const SettingSpec&, const std::vector<uint8_t>& current, int selected);
using Bytes = std::vector<uint8_t>;
inline constexpr uint8_t kData = 0x0c;
inline constexpr uint8_t kAck = 0x01;
inline constexpr size_t kMaxPayload = 4096;
// Sound Connect 13.2.0 ARM64 PowerInquiredTypeV2.initialize 0x10140d098;
// constructor arguments at 0x10140d138, 0x10140d184, 0x10140d1c8.
inline constexpr uint8_t kBatterySingle = 0x00;
inline constexpr uint8_t kBatteryLeftRight = 0x01;
inline constexpr uint8_t kBatteryCase = 0x02;
struct Frame { uint8_t type = kData, sequence = 0; Bytes payload; };
Bytes encode(const Frame&, size_t maxPayload = kMaxPayload);

class StreamDecoder {
public:
    explicit StreamDecoder(size_t maxPayload = kMaxPayload);
    std::vector<Frame> feed(const Bytes&);
    void reset();
    size_t rejectedFrames() const { return rejected_; }
private:
    size_t maxPayload_, rejected_ = 0;
    bool active_ = false, escaped_ = false;
    Bytes decoded_;
    void reject();
};

struct BatteryValue {
    int level;
    bool charging;
    bool chargingKnown = true;
    bool fullyCharged = false;
    uint8_t chargingStatus = 0;
};
struct BatteryState {
    std::optional<BatteryValue> single, left, right, caseBattery;
};
// A caller supplies the inquiry byte confirmed by IPA/device evidence. Unknown
// subtypes never become battery state. A percent outside 0...100 is never
// displayed; 0xff is provisionally treated as absent pending live evidence.
enum class BatteryLayout { Single, LeftRight, Case };
bool parseBattery(const Bytes&, uint8_t inquiry, BatteryLayout, BatteryState&);

enum class AmbientMode { Off, NoiseCancelling, Ambient };
inline constexpr uint8_t kAmbientInquiry = 0x17;
struct AmbientState {
    AmbientMode mode;
    bool focusOnVoice;
    int level;
    bool settled = true;
    uint8_t inquiry = kAmbientInquiry;
    uint8_t ncValue = 2;
};
struct AmbientRange { uint8_t mode; int minimum, maximum, step; };
struct AmbientCapabilities { std::vector<AmbientRange> ranges; };
std::optional<AmbientCapabilities> parseAmbientCapabilities(const Bytes&);
std::optional<AmbientCapabilities> parseLegacyAmbientCapabilities(const Bytes&);
std::optional<AmbientState> parseAmbient(const Bytes&);
std::optional<AmbientState> parseLegacyAmbient(const Bytes&);
Bytes setAmbient(const AmbientState&);

struct EQState {
    uint8_t preset = 0;
    std::optional<int> clearBass;
    std::optional<std::array<int, 5>> bands;
};
struct EQPreset { uint8_t id; std::string name; };
struct EQCapabilities {
    uint8_t bandCount;
    uint8_t stepCount;
    std::vector<EQPreset> presets;
    // Enabling our six-band editor requires an exact supported gain range;
    // a different capability still permits supported preset selection.
    bool supportsEditor() const { return bandCount == 6 && stepCount == 21; }
};
std::optional<EQCapabilities> parseEQCapabilities(const Bytes&);
std::optional<EQState> parseEQ(const Bytes&);
Bytes setEQPreset(uint8_t preset);
Bytes setEQCustom(int clearBass, const std::array<int, 5>& bands);

// ACK means the frame was received, not that a setting was applied. Readback
// commands must require a matching response before declaring success.
enum class TransactionStatus { Idle, Waiting, Complete, TimedOut };
class CommandTracker {
public:
    Frame begin(const Bytes&, std::optional<uint8_t> responseOpcode,
                std::optional<uint8_t> responseInquiry,
                uint64_t nowMs, uint64_t timeoutMs, uint8_t dataType = kData);
    bool observe(const Frame&);
    bool expire(uint64_t nowMs);
    void reset();
    TransactionStatus status() const { return status_; }
    bool acknowledged() const { return acknowledged_; }
    const std::optional<Bytes>& response() const { return response_; }
    const Frame& pendingFrame() const { return pending_; }
private:
    Frame pending_;
    uint8_t nextSequence_ = 0;
    uint64_t deadline_ = 0;
    TransactionStatus status_ = TransactionStatus::Idle;
    bool acknowledged_ = false;
    std::optional<uint8_t> opcode_, inquiry_;
    std::optional<Bytes> response_;
    void updateStatus();
};

// ACK duplicate packets again but avoid processing a retransmitted payload.
struct ReceiveResult { std::optional<Frame> ack; bool deliver = false; };
class ReceiveWindow {
public:
    ReceiveResult observe(const Frame&);
    void reset() { previous_.reset(); }
private:
    std::optional<Frame> previous_;
};
} // namespace wf
