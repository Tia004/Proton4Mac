/* Read-only Vulkan capability query. BSD-3-Clause. Creates no window/device. */
#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void string(const char *s) {
    putchar('"'); for (;*s;s++) { if (*s=='"' || *s=='\\') putchar('\\'); putchar(*s); } putchar('"');
}
int main(void) {
    VkApplicationInfo app = {VK_STRUCTURE_TYPE_APPLICATION_INFO}; app.apiVersion = VK_API_VERSION_1_3;
    const char *extension = VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME;
    VkInstanceCreateInfo create = {VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    create.pApplicationInfo = &app;
    uint32_t instance_count = 0; vkEnumerateInstanceExtensionProperties(NULL,&instance_count,NULL);
    VkExtensionProperties *instance_extensions = calloc(instance_count,sizeof(*instance_extensions));
    vkEnumerateInstanceExtensionProperties(NULL,&instance_count,instance_extensions);
    for (uint32_t i=0;i<instance_count;i++) if (!strcmp(instance_extensions[i].extensionName,extension)) {
        create.flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
        create.enabledExtensionCount = 1; create.ppEnabledExtensionNames = &extension;
    }
    free(instance_extensions);
    VkInstance instance; if (vkCreateInstance(&create,NULL,&instance)!=VK_SUCCESS) return 10;
    uint32_t count = 0; vkEnumeratePhysicalDevices(instance,&count,NULL);
    if (!count) { vkDestroyInstance(instance,NULL); return 11; }
    VkPhysicalDevice *devices = calloc(count,sizeof(*devices)); vkEnumeratePhysicalDevices(instance,&count,devices);
    puts("[");
    for (uint32_t i=0;i<count;i++) {
        VkPhysicalDeviceDescriptorIndexingProperties indexing = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_PROPERTIES};
        VkPhysicalDeviceProperties2 properties = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2}; properties.pNext=&indexing;
        vkGetPhysicalDeviceProperties2(devices[i],&properties);
        VkPhysicalDeviceDescriptorIndexingFeatures features_indexing = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES};
        VkPhysicalDeviceRobustness2FeaturesEXT robustness = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT};
        VkPhysicalDeviceVulkan11Features vulkan11 = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES};
        VkPhysicalDeviceVulkan12Features vulkan12 = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES};
        VkPhysicalDeviceFeatures2 features = {VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2};
        features.pNext=&features_indexing;features_indexing.pNext=&robustness;robustness.pNext=&vulkan11;vulkan11.pNext=&vulkan12;
        vkGetPhysicalDeviceFeatures2(devices[i],&features);
        uint32_t n=0;vkEnumerateDeviceExtensionProperties(devices[i],NULL,&n,NULL);
        VkExtensionProperties *extensions=calloc(n,sizeof(*extensions));vkEnumerateDeviceExtensionProperties(devices[i],NULL,&n,extensions);
        int push=0,robust=0;
        for (uint32_t j=0;j<n;j++) { push|=!strcmp(extensions[j].extensionName,VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME);robust|=!strcmp(extensions[j].extensionName,VK_EXT_ROBUSTNESS_2_EXTENSION_NAME); }
        printf("  {\"device\":"); string(properties.properties.deviceName);
        printf(",\"vulkan_version\":\"%u.%u.%u\",\"robustness2_extension\":%s,\"push_descriptor_extension\":%s,\"robustBufferAccess2\":%s,\"nullDescriptor\":%s,\"shaderDrawParameters\":%s,\"samplerMirrorClampToEdge\":%s,\"updateAfterBind\":{\"sampledImages\":%u,\"storageImages\":%u,\"storageBuffers\":%u,\"samplers\":%u},\"descriptorBindingPartiallyBound\":%s,\"runtimeDescriptorArray\":%s}%s\n",
            VK_VERSION_MAJOR(properties.properties.apiVersion),VK_VERSION_MINOR(properties.properties.apiVersion),VK_VERSION_PATCH(properties.properties.apiVersion),
            robust?"true":"false",push?"true":"false",robustness.robustBufferAccess2?"true":"false",robustness.nullDescriptor?"true":"false",vulkan11.shaderDrawParameters?"true":"false",vulkan12.samplerMirrorClampToEdge?"true":"false",
            indexing.maxDescriptorSetUpdateAfterBindSampledImages,indexing.maxDescriptorSetUpdateAfterBindStorageImages,indexing.maxDescriptorSetUpdateAfterBindStorageBuffers,indexing.maxDescriptorSetUpdateAfterBindSamplers,
            features_indexing.descriptorBindingPartiallyBound?"true":"false",features_indexing.runtimeDescriptorArray?"true":"false",i+1<count?",":"");
        free(extensions);
    }
    puts("]");free(devices);vkDestroyInstance(instance,NULL);return 0;
}
