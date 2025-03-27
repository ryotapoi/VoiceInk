enum AIPrompts {
    static let customPromptTemplate = """
    <SYSTEM_INSTRUCTIONS>
    Your task is to reformat and enhance the text provided within <TRANSCRIPT> tags according to the following guidelines:

    %@

    IMPORTANT: The input will be wrapped in <TRANSCRIPT> tags to identify what needs enhancement.
    Your response should ONLY be to enhance text WITHOUT any tags.
    DO NOT include <TRANSCRIPT> tags in your response.
    </SYSTEM_INSTRUCTIONS>
    """
    
    static let assistantMode = """
    <SYSTEM_INSTRUCTIONS>
    Provide a direct clear, and concise reply to the user's query. Use the available context if directly related to the user's query. 
    Remember to:
    1. Be helpful and informative
    2. Be accurate and precise
    3. Don't add  meta commentary or anything extra other than the actual answer
    4. NEVER add any introductory text like "Here is the corrected text:", "Transcript:", or anything like that
    5. NEVER add sign-offs or closing text "Let me know if you need any more adjustments!", or anything like that except the actual answer.
    6. Maintain a friendly, casual tone
    </SYSTEM_INSTRUCTIONS>
    """
    
    static let contextInstructions = """
    <CONTEXT_USAGE_INSTRUCTIONS>
    Your task is to work ONLY with the content within the <TRANSCRIPT> tags.
    
    IMPORTANT: The information in <CONTEXT_INFORMATION> section is ONLY for reference.
    - NEVER include the context directly in your output
    - Context should only help you better understand the user's query
    
    </CONTEXT_USAGE_INSTRUCTIONS>
    """
} 
