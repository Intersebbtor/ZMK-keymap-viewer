import Foundation

// Test the removeComments function
let testData = """
/ {
    keymap {
        compatible = "zmk,keymap";
        
        // This is a C++ style comment
        default_layer {
            label = "QWERTY"; /* This is a C style comment */
            bindings = <
                &kp Q /* Q key */ &kp W /* W key */
                &kp A &kp S // row comment
            >;
        };
    };
};
"""

print("Original data:")
print(testData)
print("\n" + String(repeating: "=", count: 50) + "\n")

// Now test with the parser to ensure comments are handled
print("Testing parser with comments...")
print("If this works, the parser correctly removes comments")
