-- TestNumericDiff.lua - Test the numeric difference detection function
local LrLogger = import "LrLogger"

local console = LrLogger("ImmichAlbumSync")
console:enable("print") -- Logs will be written to a file

-- Function to check if two album names only differ in numeric parts
local function onlyDifferInNumericParts(name1, name2)
    -- Replace all numeric sequences with a placeholder in both names
    local nonNumeric1 = string.lower(name1):gsub("%d+", "NUM")
    local nonNumeric2 = string.lower(name2):gsub("%d+", "NUM")
    
    -- If the non-numeric parts are identical, the names only differ in numbers
    return nonNumeric1 == nonNumeric2
end

-- Test cases
local testCases = {
    {
        name1 = "Vacation 2023",
        name2 = "Vacation 2022",
        expected = true,
        description = "Years differ"
    },
    {
        name1 = "Trip to Paris 2023",
        name2 = "Trip to Paris 2022",
        expected = true,
        description = "Years differ with spaces"
    },
    {
        name1 = "Family-2023",
        name2 = "Family-2022",
        expected = true,
        description = "Years differ with dash"
    },
    {
        name1 = "Wedding_20230615",
        name2 = "Wedding_20220615",
        expected = true,
        description = "Dates differ with underscore"
    },
    {
        name1 = "Birthday Party 2023",
        name2 = "Birthday Celebration 2023",
        expected = false,
        description = "Words differ, not just numbers"
    },
    {
        name1 = "Trip to Paris",
        name2 = "Trip to London",
        expected = false,
        description = "No numbers, words differ"
    },
    {
        name1 = "Trip to Paris",
        name2 = "Trip to Paris",
        expected = true,
        description = "Identical strings"
    },
    {
        name1 = "Trip 1 to Paris",
        name2 = "Trip 2 to Paris",
        expected = true,
        description = "Numbers in middle differ"
    },
    {
        name1 = "1 Trip to Paris",
        name2 = "2 Trip to Paris",
        expected = true,
        description = "Numbers at start differ"
    },
    {
        name1 = "Trip to Paris 2023-06-15",
        name2 = "Trip to Paris 2022-07-20",
        expected = true,
        description = "Complex date format differs"
    }
}

-- Run tests
local passCount = 0
local failCount = 0

console:info("Running tests for onlyDifferInNumericParts function...")

for i, test in ipairs(testCases) do
    local result = onlyDifferInNumericParts(test.name1, test.name2)
    local status = result == test.expected and "PASS" or "FAIL"
    
    if status == "PASS" then
        passCount = passCount + 1
    else
        failCount = failCount + 1
    end
    
    console:infof("[%s] Test %d: %s", status, i, test.description)
    console:infof("  Name1: '%s', Name2: '%s', Expected: %s, Got: %s", 
        test.name1, test.name2, tostring(test.expected), tostring(result))
end

console:infof("Test summary: %d passed, %d failed", passCount, failCount)

return {
    runTests = function()
        console:info("Tests already run during module load")
        return passCount, failCount
    end
}
