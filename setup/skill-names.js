"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.isReservedSkillName = isReservedSkillName;
// The user skill view keeps externally synchronized skills under synced/, and
// Claude reserves anthropic-skills, so no installed skill may use either name
// in any letter case.
function isReservedSkillName(name) {
    return /^(synced|anthropic-skills)$/i.test(name);
}
