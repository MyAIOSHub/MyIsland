//
//  PetGachaSystem.swift
//  MyIsland
//
//  Pet gacha system: rolling, collection, active pet selection, persistence.
//

import Combine
import Foundation
import os.log

private let petLogger = Logger(subsystem: "com.myisland", category: "Pet")

@MainActor
class PetGachaSystem: ObservableObject {
    static let shared = PetGachaSystem()

    @Published var collection: [Pet] = []
    @Published var activePet: Pet?
    @Published var totalRolls: Int = 0

    private let saveKey = "PetGachaCollection"
    private let activeKey = "PetGachaActivePet"
    private let rollsKey = "PetGachaTotalRolls"

    private init() {
        load()
        ensureStarterCrab()
    }

    /// Ensure the OG crab mascot is always in the collection (starter pet)
    private func ensureStarterCrab() {
        let hasStarterCrab = collection.contains { $0.species == .crab && $0.name == "小蟹OG" }
        guard !hasStarterCrab else { return }

        let starterCrab = Pet(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            species: .crab,
            rarity: .rare,
            eye: .dot,
            hat: .none,
            shiny: false,
            stats: PetStats(debugging: 50, patience: 40, chaos: 60, wisdom: 45, snark: 55),
            name: "小蟹OG",
            hatchedAt: Date(timeIntervalSince1970: 0)
        )

        collection.insert(starterCrab, at: 0)

        // Set as active if no active pet
        if activePet == nil {
            activePet = starterCrab
        }

        save()
    }

    // MARK: - Mulberry32 PRNG (same as buddy system)

    private static func mulberry32(seed: UInt32) -> () -> Double {
        var a = seed
        return {
            a &+= 0x6D2B79F5
            var t = a
            t = (t ^ (t >> 15)) &* (1 | a)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4294967296.0
        }
    }

    // MARK: - Rolling

    /// Cowsay bonus species (slightly rarer in gacha)
    private static let cowsaySpecies: Set<PetSpecies> = [
        .fox, .bunny2, .owl2, .koala, .tuxPenguin, .elephant,
        .sheep, .squirrel, .bear, .dragon2, .kitty, .cowsayCat,
    ]

    /// Build a weighted species pool: original species weight 3, cowsay species weight 1
    private static let weightedSpeciesPool: [PetSpecies] = {
        var pool: [PetSpecies] = []
        for species in PetSpecies.allCases {
            let count = cowsaySpecies.contains(species) ? 1 : 3
            for _ in 0..<count {
                pool.append(species)
            }
        }
        return pool
    }()

    /// Roll a new pet using weighted rarity system.
    func roll() -> Pet {
        totalRolls += 1

        // Seed from current time + roll count for variety
        let seed = UInt32(truncatingIfNeeded: UInt64(Date().timeIntervalSince1970 * 1000)) &+ UInt32(totalRolls)
        let rng = Self.mulberry32(seed: seed)

        let rarity = rollRarity(rng: rng)
        let species = pick(rng: rng, from: Self.weightedSpeciesPool)
        let eye = pick(rng: rng, from: PetEye.allCases)
        let hat: PetHat = rarity == .common ? .none : pick(rng: rng, from: PetHat.allCases)
        let shiny = rng() < 0.01
        let stats = rollStats(rng: rng, rarity: rarity)

        let pet = Pet(
            id: UUID(),
            species: species,
            rarity: rarity,
            eye: eye,
            hat: hat,
            shiny: shiny,
            stats: stats,
            name: generateName(species: species, rng: rng),
            hatchedAt: Date()
        )

        collection.append(pet)
        if activePet == nil {
            activePet = pet
        }
        save()
        return pet
    }

    /// Set the active pet shown in the notch.
    func setActive(_ pet: Pet) {
        activePet = pet
        save()
    }

    /// Randomly switch to a different pet from the collection.
    func randomizeActivePet() {
        let candidates = collection.filter { $0.id != activePet?.id }
        guard let newPet = candidates.randomElement() else {
            return
        }
        setActive(newPet)
    }

    // MARK: - Collection Stats

    var uniqueSpeciesCount: Int {
        Set(collection.map { $0.species }).count
    }

    var totalSpeciesCount: Int {
        PetSpecies.allCases.count
    }

    // MARK: - Private Helpers

    private func rollRarity(rng: () -> Double) -> PetRarity {
        let total = PetRarity.allCases.reduce(0) { $0 + $1.weight }
        var roll = rng() * Double(total)
        for rarity in PetRarity.allCases {
            roll -= Double(rarity.weight)
            if roll < 0 { return rarity }
        }
        return .common
    }

    private func pick<T>(rng: () -> Double, from array: [T]) -> T {
        array[Int(rng() * Double(array.count)) % array.count]
    }

    private func rollStats(rng: () -> Double, rarity: PetRarity) -> PetStats {
        let floor: Int
        switch rarity {
        case .common:    floor = 5
        case .uncommon:  floor = 15
        case .rare:      floor = 25
        case .epic:      floor = 35
        case .legendary: floor = 50
        }

        let statNames = ["debugging", "patience", "chaos", "wisdom", "snark"]
        let peakIdx = Int(rng() * Double(statNames.count)) % statNames.count
        var dumpIdx = Int(rng() * Double(statNames.count)) % statNames.count
        while dumpIdx == peakIdx {
            dumpIdx = Int(rng() * Double(statNames.count)) % statNames.count
        }

        var values = [Int](repeating: 0, count: 5)
        for i in 0..<5 {
            if i == peakIdx {
                values[i] = min(100, floor + 50 + Int(rng() * 30))
            } else if i == dumpIdx {
                values[i] = max(1, floor - 10 + Int(rng() * 15))
            } else {
                values[i] = floor + Int(rng() * 40)
            }
        }

        return PetStats(
            debugging: values[0],
            patience: values[1],
            chaos: values[2],
            wisdom: values[3],
            snark: values[4]
        )
    }

    private func generateName(species: PetSpecies, rng: () -> Double) -> String {
        let prefixes = ["小", "阿", "大", "老", "胖"]
        let suffixes: [PetSpecies: [String]] = [
            .duck: ["黄", "嘎", "鸭"],
            .goose: ["鹅", "白", "咕"],
            .blob: ["团", "软", "球"],
            .cat: ["花", "咪", "喵"],
            .dragon: ["龙", "火", "翼"],
            .octopus: ["章", "爪", "墨"],
            .owl: ["夜", "眼", "羽"],
            .penguin: ["企", "冰", "黑"],
            .turtle: ["壳", "慢", "绿"],
            .snail: ["蜗", "壳", "滑"],
            .ghost: ["幽", "灵", "白"],
            .axolotl: ["萌", "腮", "粉"],
            .capybara: ["豚", "悠", "泡"],
            .cactus: ["刺", "绿", "针"],
            .robot: ["机", "铁", "芯"],
            .rabbit: ["兔", "耳", "跳"],
            .mushroom: ["菇", "伞", "点"],
            .chonk: ["胖", "圆", "球"],
            .fox: ["狐", "灵", "赤"],
            .bunny2: ["兔", "蹦", "白"],
            .owl2: ["鸮", "夜", "智"],
            .koala: ["拉", "树", "抱"],
            .tuxPenguin: ["燕", "冰", "礼"],
            .elephant: ["象", "鼻", "大"],
            .sheep: ["羊", "毛", "绵"],
            .squirrel: ["鼠", "果", "松"],
            .bear: ["熊", "掌", "憨"],
            .dragon2: ["翼", "炎", "飞"],
            .kitty: ["猫", "柔", "爪"],
            .cowsayCat: ["野", "猫", "夜"],
        ]

        let prefix = prefixes[Int(rng() * Double(prefixes.count)) % prefixes.count]
        let speciesSuffixes = suffixes[species] ?? ["宝"]
        let suffix = speciesSuffixes[Int(rng() * Double(speciesSuffixes.count)) % speciesSuffixes.count]
        return prefix + suffix
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(collection) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
        if let activePet, let data = try? JSONEncoder().encode(activePet.id) {
            UserDefaults.standard.set(data, forKey: activeKey)
        }
        UserDefaults.standard.set(totalRolls, forKey: rollsKey)
    }

    func load() {
        totalRolls = UserDefaults.standard.integer(forKey: rollsKey)

        if let data = UserDefaults.standard.data(forKey: saveKey),
           let pets = try? JSONDecoder().decode([Pet].self, from: data) {
            collection = pets
        }

        if let idData = UserDefaults.standard.data(forKey: activeKey),
           let activeId = try? JSONDecoder().decode(UUID.self, from: idData) {
            activePet = collection.first { $0.id == activeId }
        }
    }
}
