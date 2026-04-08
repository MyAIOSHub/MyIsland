//
//  Pet.swift
//  MyIsland
//
//  Pet gacha model - species, rarities, eyes, hats, stats
//

import Foundation

// MARK: - Rarity

enum PetRarity: String, CaseIterable, Codable {
    case common, uncommon, rare, epic, legendary

    var weight: Int {
        switch self {
        case .common: return 60
        case .uncommon: return 25
        case .rare: return 10
        case .epic: return 4
        case .legendary: return 1
        }
    }

    var stars: String {
        switch self {
        case .common: return "\u{2605}"
        case .uncommon: return "\u{2605}\u{2605}"
        case .rare: return "\u{2605}\u{2605}\u{2605}"
        case .epic: return "\u{2605}\u{2605}\u{2605}\u{2605}"
        case .legendary: return "\u{2605}\u{2605}\u{2605}\u{2605}\u{2605}"
        }
    }

    var colorName: String {
        switch self {
        case .common: return "gray"
        case .uncommon: return "green"
        case .rare: return "blue"
        case .epic: return "purple"
        case .legendary: return "gold"
        }
    }

    var displayName: String {
        switch self {
        case .common: return "普通"
        case .uncommon: return "不凡"
        case .rare: return "稀有"
        case .epic: return "史诗"
        case .legendary: return "传说"
        }
    }
}

// MARK: - Species

enum PetSpecies: String, CaseIterable, Codable {
    case duck, goose, blob, cat, dragon, octopus, owl, penguin
    case turtle, snail, ghost, axolotl, capybara, cactus, robot
    case rabbit, mushroom, chonk
    // Cowsay bonus species
    case fox, bunny2, owl2, koala, tuxPenguin, elephant, sheep, squirrel
    case bear, dragon2, kitty, cowsayCat
    // Special: Claude's original mascot
    case crab

    var displayName: String {
        switch self {
        case .duck: return "鸭子"
        case .goose: return "鹅"
        case .blob: return "果冻"
        case .cat: return "猫咪"
        case .dragon: return "龙"
        case .octopus: return "章鱼"
        case .owl: return "猫头鹰"
        case .penguin: return "企鹅"
        case .turtle: return "乌龟"
        case .snail: return "蜗牛"
        case .ghost: return "幽灵"
        case .axolotl: return "六角恐龙"
        case .capybara: return "水豚"
        case .cactus: return "仙人掌"
        case .robot: return "机器人"
        case .rabbit: return "兔子"
        case .mushroom: return "蘑菇"
        case .chonk: return "胖猫"
        case .fox: return "狐狸"
        case .bunny2: return "小兔"
        case .owl2: return "鸮"
        case .koala: return "考拉"
        case .tuxPenguin: return "燕尾企鹅"
        case .elephant: return "大象"
        case .sheep: return "绵羊"
        case .squirrel: return "松鼠"
        case .bear: return "熊"
        case .dragon2: return "飞龙"
        case .kitty: return "小猫"
        case .cowsayCat: return "野猫"
        case .crab: return "螃蟹"
        }
    }

    var emoji: String {
        switch self {
        case .duck: return "🦆"
        case .goose: return "🪿"
        case .blob: return "🫠"
        case .cat: return "🐱"
        case .dragon: return "🐉"
        case .octopus: return "🐙"
        case .owl: return "🦉"
        case .penguin: return "🐧"
        case .turtle: return "🐢"
        case .snail: return "🐌"
        case .ghost: return "👻"
        case .axolotl: return "🦎"
        case .capybara: return "🦫"
        case .cactus: return "🌵"
        case .robot: return "🤖"
        case .rabbit: return "🐰"
        case .mushroom: return "🍄"
        case .chonk: return "😺"
        case .fox: return "🦊"
        case .bunny2: return "🐇"
        case .owl2: return "🦉"
        case .koala: return "🐨"
        case .tuxPenguin: return "🐧"
        case .elephant: return "🐘"
        case .sheep: return "🐑"
        case .squirrel: return "🐿️"
        case .bear: return "🐻"
        case .dragon2: return "🐲"
        case .kitty: return "🐈"
        case .cowsayCat: return "🐈‍⬛"
        case .crab: return "🦀"
        }
    }
}

// MARK: - Eye

enum PetEye: String, CaseIterable, Codable {
    case dot = "\u{00B7}"
    case star = "\u{2726}"
    case cross = "\u{00D7}"
    case circle = "\u{25C9}"
    case at = "@"
    case degree = "\u{00B0}"
}

// MARK: - Hat

enum PetHat: String, CaseIterable, Codable {
    case none, crown, tophat, propeller, halo, wizard, beanie, tinyduck

    var displayName: String {
        switch self {
        case .none: return "无"
        case .crown: return "皇冠"
        case .tophat: return "礼帽"
        case .propeller: return "螺旋桨帽"
        case .halo: return "光环"
        case .wizard: return "巫师帽"
        case .beanie: return "毛线帽"
        case .tinyduck: return "小鸭子"
        }
    }
}

// MARK: - Stats

struct PetStats: Codable {
    var debugging: Int
    var patience: Int
    var chaos: Int
    var wisdom: Int
    var snark: Int

    var asDictionary: [(String, Int)] {
        [
            ("DEBUGGING", debugging),
            ("PATIENCE", patience),
            ("CHAOS", chaos),
            ("WISDOM", wisdom),
            ("SNARK", snark),
        ]
    }
}

// MARK: - Pet

struct Pet: Identifiable, Codable {
    let id: UUID
    let species: PetSpecies
    let rarity: PetRarity
    let eye: PetEye
    let hat: PetHat
    let shiny: Bool
    let stats: PetStats
    var name: String
    var hatchedAt: Date

    /// ASCII art frames (3 frames per species)
    var frames: [[String]] {
        PetSprites.frames(for: species, eye: eye, hat: hat)
    }

    /// Face string for compact display
    var face: String {
        PetSprites.face(for: species, eye: eye)
    }
}
