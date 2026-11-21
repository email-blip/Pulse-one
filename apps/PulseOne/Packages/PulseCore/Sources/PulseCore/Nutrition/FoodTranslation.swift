import Foundation

/// German search terms for common generic foods, mapped to the English USDA wording
/// (NUTRITION-SPEC §4: own translation table until the BLS licence is cleared).
public enum FoodTranslation {
    static let germanToEnglish: [String: String] = [
        "apfel": "apple raw", "banane": "banana raw", "birne": "pear raw", "orange": "orange raw",
        "mandarine": "tangerine raw", "erdbeere": "strawberries raw", "erdbeeren": "strawberries raw",
        "heidelbeeren": "blueberries raw", "himbeeren": "raspberries raw", "weintrauben": "grapes raw",
        "kiwi": "kiwifruit raw", "ananas": "pineapple raw", "mango": "mango raw", "avocado": "avocado raw",
        "zitrone": "lemon raw", "tomate": "tomatoes red raw", "tomaten": "tomatoes red raw",
        "gurke": "cucumber raw", "karotte": "carrots raw", "karotten": "carrots raw", "möhre": "carrots raw",
        "möhren": "carrots raw", "paprika": "peppers sweet red raw", "brokkoli": "broccoli raw",
        "blumenkohl": "cauliflower raw", "spinat": "spinach raw", "salat": "lettuce raw", "kopfsalat": "lettuce raw",
        "zwiebel": "onions raw", "knoblauch": "garlic raw", "zucchini": "squash zucchini raw",
        "kartoffel": "potatoes boiled", "kartoffeln": "potatoes boiled", "süßkartoffel": "sweet potato raw",
        "pilze": "mushrooms white raw", "champignons": "mushrooms white raw", "erbsen": "peas green raw",
        "mais": "corn sweet yellow raw", "linsen": "lentils cooked", "kichererbsen": "chickpeas cooked",
        "bohnen": "beans kidney cooked", "haferflocken": "oats", "reis": "rice white cooked",
        "vollkornreis": "rice brown cooked", "nudeln": "pasta cooked", "spaghetti": "spaghetti cooked",
        "quinoa": "quinoa cooked", "brot": "bread whole wheat", "vollkornbrot": "bread whole wheat",
        "weißbrot": "bread white", "brötchen": "rolls hard", "ei": "egg whole raw", "eier": "egg whole raw",
        "milch": "milk whole", "joghurt": "yogurt plain whole milk", "quark": "cheese cottage lowfat",
        "käse": "cheese cheddar", "butter": "butter salted", "olivenöl": "oil olive", "rapsöl": "oil canola",
        "hähnchen": "chicken breast cooked", "hähnchenbrust": "chicken breast cooked", "pute": "turkey breast cooked",
        "rindfleisch": "beef ground cooked", "hackfleisch": "beef ground cooked", "schweinefleisch": "pork loin cooked",
        "lachs": "salmon atlantic cooked", "thunfisch": "tuna canned water", "forelle": "trout cooked",
        "walnüsse": "nuts walnuts", "mandeln": "nuts almonds", "haselnüsse": "nuts hazelnuts",
        "erdnüsse": "peanuts raw", "honig": "honey", "zucker": "sugars granulated", "tofu": "tofu raw",
        "kaffee": "coffee brewed", "tee": "tea brewed", "orangensaft": "orange juice raw", "apfelsaft": "apple juice"
    ]

    /// English USDA query for a German term, or nil if none is known.
    public static func english(for german: String) -> String? {
        germanToEnglish[german.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }
}
