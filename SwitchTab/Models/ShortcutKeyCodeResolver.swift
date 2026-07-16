enum ShortcutKeyCodeResolver {
    static func keyEquivalent(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 0:
            return "A"
        case 1:
            return "S"
        case 2:
            return "D"
        case 3:
            return "F"
        case 4:
            return "H"
        case 5:
            return "G"
        case 6:
            return "Z"
        case 7:
            return "X"
        case 8:
            return "C"
        case 9:
            return "V"
        case 11:
            return "B"
        case 12:
            return "Q"
        case 13:
            return "W"
        case 14:
            return "E"
        case 15:
            return "R"
        case 16:
            return "Y"
        case 17:
            return "T"
        case 18:
            return "1"
        case 19:
            return "2"
        case 20:
            return "3"
        case 21:
            return "4"
        case 22:
            return "6"
        case 23:
            return "5"
        case 24:
            return "="
        case 25:
            return "9"
        case 26:
            return "7"
        case 27:
            return "-"
        case 28:
            return "8"
        case 29:
            return "0"
        case 30:
            return "]"
        case 31:
            return "O"
        case 32:
            return "U"
        case 33:
            return "["
        case 34:
            return "I"
        case 35:
            return "P"
        case 36:
            return "Return"
        case 37:
            return "L"
        case 38:
            return "J"
        case 39:
            return "'"
        case 40:
            return "K"
        case 41:
            return ";"
        case 42:
            return "\\"
        case 43:
            return ","
        case 44:
            return "/"
        case 45:
            return "N"
        case 46:
            return "M"
        case 47:
            return "."
        case 48:
            return "Tab"
        case 49:
            return "Space"
        case 50:
            return "`"
        case 51:
            return "Delete"
        case 53:
            return "Esc"
        default:
            return nil
        }
    }

    static func keyCode(for keyEquivalent: String) -> UInt16? {
        switch keyEquivalent {
        case "tab", "Tab", "\t":
            return 48
        case "space", "Space", " ":
            return 49
        case "return", "Return", "\r":
            return 36
        case "delete", "Delete", "\u{7F}":
            return 51
        case "esc", "Esc", "escape", "Escape", "\u{1B}":
            return 53
        default:
            break
        }

        let utf8 = keyEquivalent.utf8
        guard utf8.count == 1, let byte = utf8.first else {
            return nil
        }

        switch byte {
        case 65, 97:
            return 0
        case 83, 115:
            return 1
        case 68, 100:
            return 2
        case 70, 102:
            return 3
        case 72, 104:
            return 4
        case 71, 103:
            return 5
        case 90, 122:
            return 6
        case 88, 120:
            return 7
        case 67, 99:
            return 8
        case 86, 118:
            return 9
        case 66, 98:
            return 11
        case 81, 113:
            return 12
        case 87, 119:
            return 13
        case 69, 101:
            return 14
        case 82, 114:
            return 15
        case 89, 121:
            return 16
        case 84, 116:
            return 17
        case 49:
            return 18
        case 50:
            return 19
        case 51:
            return 20
        case 52:
            return 21
        case 54:
            return 22
        case 53:
            return 23
        case 61:
            return 24
        case 57:
            return 25
        case 55:
            return 26
        case 45:
            return 27
        case 56:
            return 28
        case 48:
            return 29
        case 93:
            return 30
        case 79, 111:
            return 31
        case 85, 117:
            return 32
        case 91:
            return 33
        case 73, 105:
            return 34
        case 80, 112:
            return 35
        case 76, 108:
            return 37
        case 74, 106:
            return 38
        case 39:
            return 39
        case 75, 107:
            return 40
        case 59:
            return 41
        case 92:
            return 42
        case 44:
            return 43
        case 47:
            return 44
        case 78, 110:
            return 45
        case 77, 109:
            return 46
        case 46:
            return 47
        case 32:
            return 49
        case 96:
            return 50
        case 127:
            return 51
        default:
            return nil
        }
    }
}
