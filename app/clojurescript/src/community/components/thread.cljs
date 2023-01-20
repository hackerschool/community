(ns community.components.thread
  (:require [community.state :as state]
            [community.controller :as controller]
            [community.util :as util :refer-macros [<? p]]
            [community.models :as models]
            [community.partials :as partials :refer [link-to]]
            [community.routes :as routes]
            [community.components.shared :as shared]
            [community.components.subforum-info :refer [subforum-info-header]]
            [om.core :as om]
            [om-tools.core :refer-macros [defcomponent]]
            [sablono.core :refer-macros [html]]
            [cljs.core.async :as async]
            [clojure.string :as str])
  (:require-macros [cljs.core.async.macros :refer [go go-loop]]))

(defcomponent post-form [{:keys [post autocomplete-users broadcast-groups]} owner]
  (display-name [_] "PostForm")

  (init-state [_]
    {:original-post-body (:body post)})

  (render [_]
    (html
      [:div
       (let [errors (:errors post)]
         (if (not (empty? errors))
           [:div (map (fn [e] [:p.text-danger e]) errors)]))
       [:form {:onSubmit (fn [e]
                           (.preventDefault e)
                           (when-not (:submitting? @post)
                             (if (:persisted? @post)
                               (controller/dispatch :update-post @post)
                               (controller/dispatch :new-post @post))))}
        [:div.post-form-body
         (when (not (:persisted? post))
           [:div.form-group
            (shared/->broadcast-group-picker
             {:broadcast-groups (mapv #(assoc % :selected? (contains? (:broadcast-to post) (:id %)))
                                      broadcast-groups)}
             {:opts {:on-toggle (fn [id]
                                  (om/transact! post :broadcast-to #(models/toggle-broadcast-to % id)))}})])
         (let [post-body-id (str "post-body-" (or (:id post) "new"))]
           [:div.form-group
            [:label.hidden {:for post-body-id} "Body"]
            (shared/->autocompleting-textarea
             {:value (:body post)
              :autocomplete-list (mapv :name autocomplete-users)}
             {:opts {:focus? (:persisted? post)
                     :on-change #(om/update! post :body %)
                     :passthrough
                     {:id post-body-id
                      :class ["form-control" "post-textarea"]
                      :name "post[body]"
                      :data-new-anchor true
                      :placeholder "Compose your post..."}}})])]
        [:div.row.no-side-margin
         [:div.post-form-controls
          (if (:persisted? post)
            [:div
             [:button.post-update
              {:type "submit"
               :disabled (:submitting? post)}
              "Update"]
             [:button.post-cancel-update
              {:type "button"
               :onClick (fn [e]
                          (om/update! post :body (om/get-state owner :original-post-body))
                          (om/update! post :editing? false))}
              "Cancel"]]
            [:button.btn.btn-default.btn-sm {:type "submit"
                                             :disabled (:submitting? post)}
             "Post"])]
         ;; only show markdown help for new posts, not when editing
         (when (not (:persisted? post))
           (partials/markdown-help))]]])))

(defn post-number-id [n]
  (str "post-number-" n))

(defcomponent post [{:keys [post autocomplete-users highlight? in-series?]} owner]
  (display-name [_] "Post")

  (render [_]
    (html
      [:li.post {:id (post-number-id (:post-number post))
                 :class [(when highlight? "post-highlight")
                         (when in-series? "post-in-series")]}
       [:div.row
        [:div.post-author-image
         [:a {:href (routes/hs-route :person (:author post))}
          [:img
           {:src (-> post :author :avatar-url)
            :width "50"       ;TODO: request different image sizes
            }]]]
        [:div.post-metadata
         [:a.author-name {:href (routes/hs-route :person (:author post))}
          (-> post :author :name)]
         [:div.batch-name (-> post :author :batch-name)]
         [:div.timestamp (util/human-format-time (:created-at post))]]
        [:div.post-content
         (if (:editing? post)
           (->post-form {:post post
                         :autocomplete-users autocomplete-users})
           [:div
            [:div.post-body
             (partials/html-from-markdown
              (partials/wrap-mentions (:body post) autocomplete-users))]
            [:div.post-controls
             (when (and (:editable post) (not (:editing? post)))
               [:button.post-edit
                {:onClick (fn [e]
                            (.preventDefault e)
                            (om/update! post :editing? true))}
                [:span [:i.fa.fa-pencil] " Edit"]])]])]]])))

(defn scroll-to-post-number [post-number]
  (when post-number
    (let [scroll-pos (-> js/document
                         (.getElementById (post-number-id post-number))
                         (.getBoundingClientRect)
                         (.-top)
                         (- 100))]
      (.scrollTo js/window 0 scroll-pos))))

(defcomponent thread [{:keys [thread route-data current-user]} owner]
  (display-name [_] "Thread")

  (init-state [_]
    {:active-tab :compose})

  (did-mount [_]
    (scroll-to-post-number (:post-number route-data)))

  (did-update [_ prev-props prev-state]
    (if-not (= (:post-number (:route-data prev-props))
               (:post-number route-data))
      (scroll-to-post-number (:post-number route-data))))

  (render-state [_ {:keys [active-tab]}]
    (let [autocomplete-users (:autocomplete-users thread)]
      (html
        [:div#thread-view
         [:div.t-title
          [:h3
           (when (:pinned thread) [:i.fa.fa-thumb-tack.pinned-icon])
           (:title thread)]
          (when (models/admin? current-user)
            [:button.btn.btn-link.btn-xs
             {:onClick #(controller/dispatch :toggle-thread-pinned @thread)}
             (if (:pinned thread)
               "unpin"
               [:span [:i.fa.fa-thumb-tack] "pin"])])]

         [:div.row.no-side-margin
          [:div.subscribe (shared/->subscription-info (:subscription thread))]
          [:div.new-item-button.hidden-xs (partials/new-anchor-button "New post" {:class ["btn" "btn-link"]})]]

         [:div.row.no-side-margin
          [:div.hidden-xs (subforum-info-header
                           (assoc (:subforum thread)
                             :n-thread-subscribers (:n-subscribers thread))
                           {:title-link? true})]
          [:div.t-threads
           [:div.t-top-bar {:style {:background-color (:ui-color thread)}}]
           [:ol.list-unstyled
            (for [[last-post post] (map vector (cons nil (:posts thread))
                                               (:posts thread))]
              (let [in-series? (= (:id (:author last-post))
                                  (:id (:author post)))]
                (->post {:post post
                         :autocomplete-users autocomplete-users
                         :highlight? (= (str (:post-number post)) (:post-number route-data))
                         :in-series? in-series?}
                        {:react-key (:id post)})))]]]

         [:div.row.no-side-margin
          [:div.new-post
           (shared/->tabbed-panel
            {:tabs [{:id :compose
                     :body "Compose"
                     :view-fn ->post-form}
                    {:id :preview
                     :body "Preview"
                     :view-fn shared/->post-preview}]
             :props {:broadcast-groups (:broadcast-groups thread)
                     :autocomplete-users autocomplete-users
                     :post (assoc (:new-post thread)
                             :errors (:errors thread)
                             :submitting? (:submitting? thread))}})]]]))))
